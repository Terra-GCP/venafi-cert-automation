#!/usr/bin/env python3

from __future__ import annotations

import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509

from cert_ops import split_pkcs12
from config import Settings, load_settings
from discover import DiscoveredCert, discover_project_certs
from events import emit_cert_event
from notify import publish_result
from secret_manager import get_latest_secret_bytes, upload_cert_and_key
from venafi_client import VenafiClient


@dataclass(frozen=True)
class CertTarget:
    name: str
    certificate_dn: str
    secret_cert_name: str
    secret_key_name: str
    common_name: str


def _days_left_from_pem(cert_pem: bytes) -> tuple[int, str]:
    cert = x509.load_pem_x509_certificate(cert_pem)
    valid_to = cert.not_valid_after_utc.astimezone(timezone.utc)
    days_left = (valid_to - datetime.now(timezone.utc)).days
    return days_left, valid_to.strftime("%Y-%m-%d %H:%M:%SZ")


def _to_target(settings: Settings, client: VenafiClient, discovered: DiscoveredCert) -> CertTarget:
    dn = client.resolve_certificate_dn(
        common_name=discovered.common_name,
        preferred_dn=discovered.certificate_dn,
        dn_prefix=settings.venafi_dn_prefix,
    )
    return CertTarget(
        name=discovered.name,
        certificate_dn=dn,
        secret_cert_name=discovered.secret_cert_name,
        secret_key_name=discovered.secret_key_name,
        common_name=discovered.common_name,
    )


def _sync_one(settings: Settings, client: VenafiClient, target: CertTarget) -> str:
    """Process one discovered cert. Returns status: renewed|uploaded|skipped."""
    secret_cert = target.secret_cert_name
    secret_key = target.secret_key_name
    threshold = settings.renew_days_before

    print(f"--- Cert '{target.name}' ---")
    print(f"CN        : {target.common_name}")
    print(f"DN        : {target.certificate_dn}")
    print(f"Secrets   : {secret_cert} / {secret_key}")
    print(f"Renew if <= {threshold} days (force={settings.force_renew})")

    current_pem = get_latest_secret_bytes(settings.gcp_project_id, secret_cert)
    if current_pem and not settings.force_renew:
        days_left, expiry = _days_left_from_pem(current_pem)
        print(f"Current secret expiry: {expiry} ({days_left} days left)")
        if days_left > threshold:
            summary = (
                f"Skipped '{target.name}': not due "
                f"({days_left} days left > {threshold}; expires {expiry})"
            )
            message = {
                "status": "skipped",
                "cert_name": target.name,
                "common_name": target.common_name,
                "certificate_dn": target.certificate_dn,
                "reason": "not_due",
                "days_left": days_left,
                "renew_days_before": threshold,
                "expiry": expiry,
                "summary": summary,
            }
            publish_result(settings.gcp_project_id, settings.notify_topic, message)
            emit_cert_event(
                "skipped",
                cert_name=target.name,
                common_name=target.common_name,
                certificate_dn=target.certificate_dn,
                reason="not_due",
                days_left=days_left,
                expiry=expiry,
                summary=summary,
            )
            print(f"SKIPPED: {summary}")
            return "skipped"

    renewed = False
    if settings.renew_enabled:
        renew_result = client.renew_certificate(target.certificate_dn)
        renewed = True
        print(f"Renew     : ok ({renew_result.get('ValidTo', 'requested')})")

    cert_version = ""
    key_version = ""
    with tempfile.TemporaryDirectory() as tmp:
        package_path = Path(tmp) / f"{target.name}.p12"
        client.download_pkcs12(package_path, target.certificate_dn)
        print(f"Downloaded package ({package_path.stat().st_size} bytes)")

        split = split_pkcs12(package_path, settings.p12_password)
        print(f"Subject   : {split.subject}")
        print(f"Expiry    : {split.not_after}")
        print(f"Key match : {split.key_matches}")
        if not split.key_matches:
            raise RuntimeError("Certificate and private key do not match")

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

    status = "renewed" if renewed else "uploaded"
    summary = (
        f"{'Renewed' if renewed else 'Uploaded'} certificate '{target.name}' "
        f"({split.subject}); new expiry {split.not_after}; "
        f"Secret Manager {secret_cert} version {cert_version}"
    )
    message = {
        "status": "success",
        "cert_name": target.name,
        "common_name": target.common_name,
        "certificate_dn": target.certificate_dn,
        "renewed": renewed,
        "expiry": split.not_after,
        "subject": split.subject,
        "secret_cert": secret_cert,
        "secret_key": secret_key,
        "secret_cert_version": cert_version,
        "secret_key_version": key_version,
        "summary": summary,
    }
    publish_result(settings.gcp_project_id, settings.notify_topic, message)
    emit_cert_event(
        status,
        cert_name=target.name,
        common_name=target.common_name,
        certificate_dn=target.certificate_dn,
        secret_cert=secret_cert,
        secret_key=secret_key,
        secret_cert_version=str(cert_version),
        secret_key_version=str(key_version),
        expiry=split.not_after,
        subject=split.subject,
        summary=summary,
    )
    print(f"SUCCESS: {summary}")
    return status


def main() -> int:
    settings = load_settings()
    print("=== Venafi Certificate Sync ===")
    print(f"Platform  : {settings.platform}")
    print(f"Base URL  : {settings.base_url}")
    print(f"Project   : {settings.gcp_project_id}")
    print(
        f"Discovery : secrets ending with '{settings.secret_cert_suffix}' "
        f"(key pair '{settings.secret_key_suffix}')"
    )
    print(f"Exclude   : {settings.secret_exclude_prefixes or '(none)'}")
    print(f"Renew window: <= {settings.renew_days_before} days (force={settings.force_renew})")
    print("Scope     : discover Secret Manager, renew due certs, write new versions")

    discovered = discover_project_certs(
        settings.gcp_project_id,
        cert_suffix=settings.secret_cert_suffix,
        key_suffix=settings.secret_key_suffix,
        exclude_prefixes=settings.secret_exclude_prefixes,
        dn_label_key=settings.venafi_dn_label_key,
    )
    print(f"Discovered: {len(discovered)} certificate secret pair(s)")
    for item in discovered:
        due = (
            "unknown"
            if item.days_left is None
            else f"{item.days_left}d left (expires {item.expiry})"
        )
        dn_hint = item.certificate_dn or f"(resolve via CN={item.common_name})"
        print(f"  - {item.name}: {due}; DN {dn_hint}")

    if not discovered:
        summary = (
            "No certificate secrets found in Secret Manager. "
            f"Create secrets named *{settings.secret_cert_suffix} with a paired "
            f"*{settings.secret_key_suffix}, then re-run."
        )
        print(f"=== {summary} ===")
        emit_cert_event("run_complete", summary=summary, discovered=0)
        publish_result(
            settings.gcp_project_id,
            settings.notify_topic,
            {"status": "run_complete", "summary": summary, "counts": {"discovered": 0}},
        )
        return 0

    client = VenafiClient(settings)
    auth_mode = client.authenticate()
    print(f"Auth      : ok ({auth_mode})")

    counts = {"renewed": 0, "uploaded": 0, "skipped": 0, "failed": 0}
    failures: list[str] = []

    for item in discovered:
        try:
            target = _to_target(settings, client, item)
            status = _sync_one(settings, client, target)
            counts[status] = counts.get(status, 0) + 1
        except Exception as exc:
            counts["failed"] += 1
            summary = (
                f"Failed syncing certificate '{item.name}' "
                f"(CN={item.common_name}): {str(exc)[:300]}"
            )
            failures.append(summary)
            publish_result(
                settings.gcp_project_id,
                settings.notify_topic,
                {
                    "status": "failure",
                    "cert_name": item.name,
                    "common_name": item.common_name,
                    "error": str(exc)[:500],
                    "summary": summary,
                },
            )
            emit_cert_event(
                "failed",
                cert_name=item.name,
                common_name=item.common_name,
                error=str(exc)[:500],
                summary=summary,
            )
            print(f"FAILED: {summary}")

    run_summary = (
        f"Sync finished for {len(discovered)} discovered cert(s): "
        f"renewed={counts['renewed']} uploaded={counts['uploaded']} "
        f"skipped={counts['skipped']} failed={counts['failed']}"
    )
    print(f"=== {run_summary} ===")
    emit_cert_event(
        "run_complete",
        summary=run_summary,
        renewed=counts["renewed"],
        uploaded=counts["uploaded"],
        skipped=counts["skipped"],
        failed=counts["failed"],
        discovered=len(discovered),
    )
    publish_result(
        settings.gcp_project_id,
        settings.notify_topic,
        {
            "status": "run_complete",
            "summary": run_summary,
            "counts": counts,
            "failures": failures[:20],
        },
    )

    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
