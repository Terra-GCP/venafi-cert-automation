from __future__ import annotations

import os
from dataclasses import dataclass


def _require(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required env var: {name}")
    return value


def _bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y"}


def _int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    return int(raw.strip())


@dataclass(frozen=True)
class Settings:
    platform: str
    base_url: str
    username: str
    password: str
    access_token: str
    api_key: str
    certificate_dn: str
    p12_password: str
    tls_verify: bool
    cert_name: str
    gcp_project_id: str
    secret_cert_name: str
    secret_key_name: str
    create_secrets_if_missing: bool
    notify_topic: str
    cert_install_method: str
    cert_map_name: str
    cert_map_entry_name: str
    tf_cloudbuild_trigger: str
    tf_cloudbuild_trigger_region: str
    region: str
    renew_enabled: bool
    renew_days_before: int
    force_renew: bool


def load_settings() -> Settings:
    platform = os.getenv("VENAFI_PLATFORM", "mock").strip().lower()
    if platform not in {"mock", "tpp", "cloud"}:
        raise SystemExit("VENAFI_PLATFORM must be mock, tpp, or cloud")

    method = os.getenv("CERT_INSTALL_METHOD", "none").strip().lower()
    if method not in {"cm_api", "tf_cloudbuild", "none"}:
        raise SystemExit("CERT_INSTALL_METHOD must be cm_api, tf_cloudbuild, or none")

    return Settings(
        platform=platform,
        base_url=_require("VENAFI_BASE_URL").rstrip("/"),
        username=os.getenv("VENAFI_USERNAME", "").strip(),
        password=os.getenv("VENAFI_PASSWORD", "").strip(),
        access_token=os.getenv("VENAFI_ACCESS_TOKEN", "").strip(),
        api_key=os.getenv("VENAFI_API_KEY", "").strip(),
        certificate_dn=_require("VENAFI_CERTIFICATE_DN"),
        p12_password=_require("VENAFI_P12_PASSWORD"),
        tls_verify=_bool("VENAFI_TLS_VERIFY", True),
        cert_name=os.getenv("CERT_NAME", "app-tls").strip() or "app-tls",
        gcp_project_id=_require("GCP_PROJECT_ID"),
        secret_cert_name=os.getenv("SECRET_CERT_NAME", "").strip(),
        secret_key_name=os.getenv("SECRET_KEY_NAME", "").strip(),
        create_secrets_if_missing=_bool("CREATE_SECRETS_IF_MISSING", True),
        notify_topic=os.getenv("NOTIFY_TOPIC", "").strip(),
        cert_install_method=method,
        cert_map_name=os.getenv("CERT_MAP_NAME", "").strip(),
        cert_map_entry_name=os.getenv("CERT_MAP_ENTRY_NAME", "").strip(),
        tf_cloudbuild_trigger=os.getenv("TF_CLOUDBUILD_TRIGGER", "").strip(),
        tf_cloudbuild_trigger_region=os.getenv("TF_CLOUDBUILD_TRIGGER_REGION", "").strip()
        or os.getenv("GCP_REGION", "us-central1").strip()
        or "us-central1",
        region=os.getenv("GCP_REGION", "us-central1").strip() or "us-central1",
        renew_enabled=_bool("RENEW_ENABLED", True),
        renew_days_before=_int("RENEW_DAYS_BEFORE", 30),
        force_renew=_bool("FORCE_RENEW", False),
    )
