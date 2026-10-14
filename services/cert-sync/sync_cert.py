#!/usr/bin/env python3

from __future__ import annotations

import tempfile
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509

from cert_manager import rotate_certificate
from cert_ops import split_pkcs12
from cloudbuild_trigger import run_trigger_and_wait
from config import load_settings
from notify import publish_result
from secret_manager import get_latest_secret_bytes, upload_cert_and_key
from venafi_client import VenafiClient


def _days_left_from_pem(cert_pem: bytes) -> tuple[int, str]:
    cert = x509.load_pem_x509_certificate(cert_pem)
    valid_to = cert.not_valid_after_utc.astimezone(timezone.utc)
    days_left = (valid_to - datetime.now(timezone.utc)).days
    return days_left, valid_to.strftime("%Y-%m-%d %H:%M:%SZ")


def main() -> int:
    settings = load_settings()
    step = "init"
    cert_name = settings.cert_name
    secret_cert = settings.secret_cert_name or f"{cert_name}-certificate"
    secret_key = settings.secret_key_name or f"{cert_name}-private-key"
    split = None
    renewed = False
    install_method = "none"

    try:
        print("=== Venafi Certificate Sync ===")
        print(f"Platform  : {settings.platform}")
        print(f"Base URL  : {settings.base_url}")
        print(f"Cert DN   : {settings.certificate_dn}")
        print(f"Cert name : {cert_name}")
        print(f"Install   : {settings.cert_install_method}")
        print(f"Renew if <= {settings.renew_days_before} days (force={settings.force_renew})")

        step = "expiry_check"
        current_pem = get_latest_secret_bytes(settings.gcp_project_id, secret_cert)
        if current_pem and not settings.force_renew:
            days_left, expiry = _days_left_from_pem(current_pem)
            print(f"Current secret expiry: {expiry} ({days_left} days left)")
            if days_left > settings.renew_days_before:
                message = {
                    "status": "skipped",
                    "cert_name": cert_name,
                    "reason": "not_due",
                    "days_left": days_left,
                    "renew_days_before": settings.renew_days_before,
                    "expiry": expiry,
                }
                publish_result(settings.gcp_project_id, settings.notify_topic, message)
                print(
                    f"SKIPPED: Cert '{cert_name}' not due "
                    f"({days_left} days left > {settings.renew_days_before})."
                )
                return 0

        step = "authenticate"
        client = VenafiClient(settings)
        auth_mode = client.authenticate()
        print(f"Auth      : ok ({auth_mode})")

        if settings.renew_enabled:
            step = "renew"
            renew_result = client.renew_certificate()
            renewed = True
            print(f"Renew     : ok ({renew_result.get('ValidTo', 'requested')})")

        step = "download"
        with tempfile.TemporaryDirectory() as tmp:
            package_path = Path(tmp) / f"{cert_name}.p12"
            client.download_pkcs12(package_path)
            print(f"Downloaded package ({package_path.stat().st_size} bytes)")

            step = "decrypt_split"
            split = split_pkcs12(package_path, settings.p12_password)
            print(f"Subject   : {split.subject}")
            print(f"Expiry    : {split.not_after}")
            print(f"Key match : {split.key_matches}")
            if not split.key_matches:
                raise SystemExit("Certificate and private key do not match")

            step = "secret_manager"
            cert_version, key_version = upload_cert_and_key(
                project_id=settings.gcp_project_id,
                secret_cert_name=secret_cert,
                secret_key_name=secret_key,
                cert_pem=split.cert_pem,
                key_pem=split.key_pem,
                create_if_missing=settings.create_secrets_if_missing,
            )
            print(f"Secret cert version : {cert_version}")
            print(f"Secret key version  : {key_version}")

        if settings.cert_install_method == "cm_api":
            step = "certificate_manager"
            if not settings.cert_map_name or not settings.cert_map_entry_name:
                print("CM API selected but cert map not configured yet; secrets uploaded only")
            else:
                cert_resource = rotate_certificate(
                    project_id=settings.gcp_project_id,
                    map_name=settings.cert_map_name,
                    entry_name=settings.cert_map_entry_name,
                    cert_name_prefix=settings.cert_name,
                    pem_certificate=split.cert_pem.decode("utf-8"),
                    pem_private_key=split.key_pem.decode("utf-8"),
                )
                print(f"Certificate Manager (API) updated: {cert_resource}")
                install_method = "cm_api"

        elif settings.cert_install_method == "tf_cloudbuild":
            step = "tf_cloudbuild_trigger"
            if not settings.tf_cloudbuild_trigger:
                raise SystemExit("TF_CLOUDBUILD_TRIGGER is required for tf_cloudbuild install")
            build_id = run_trigger_and_wait(
                project_id=settings.gcp_project_id,
                location=settings.tf_cloudbuild_trigger_region,
                trigger_id=settings.tf_cloudbuild_trigger,
                mode="apply",
            )
            print(f"Terraform Cloud Build trigger finished: {build_id}")
            install_method = "tf_cloudbuild"

        message = {
            "status": "success",
            "cert_name": cert_name,
            "renewed": renewed,
            "expiry": split.not_after,
            "subject": split.subject,
            "secret_cert": secret_cert,
            "secret_key": secret_key,
            "install_method": install_method,
        }
        publish_result(settings.gcp_project_id, settings.notify_topic, message)
        action = "renewed and uploaded" if renewed else "uploaded"
        print(f"SUCCESS: Cert '{cert_name}' {action}. New expiry is {split.not_after}.")
        return 0
    except Exception as exc:
        publish_result(
            settings.gcp_project_id,
            settings.notify_topic,
            {
                "status": "failure",
                "cert_name": cert_name,
                "failed_at": step,
                "error": str(exc)[:500],
            },
        )
        raise


if __name__ == "__main__":
    raise SystemExit(main())
