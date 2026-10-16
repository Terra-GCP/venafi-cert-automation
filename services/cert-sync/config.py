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


def _csv(name: str) -> tuple[str, ...]:
    raw = os.getenv(name, "").strip()
    if not raw:
        return ()
    return tuple(part.strip() for part in raw.split(",") if part.strip())


@dataclass(frozen=True)
class Settings:
    platform: str
    base_url: str
    username: str
    password: str
    access_token: str
    api_key: str
    p12_password: str
    tls_verify: bool
    gcp_project_id: str
    create_secrets_if_missing: bool
    notify_topic: str
    region: str
    renew_enabled: bool
    renew_days_before: int
    force_renew: bool
    secret_cert_suffix: str
    secret_key_suffix: str
    secret_exclude_prefixes: tuple[str, ...]
    venafi_dn_label_key: str
    venafi_dn_prefix: str


def load_settings() -> Settings:
    platform = os.getenv("VENAFI_PLATFORM", "tpp").strip().lower()
    if platform not in {"mock", "tpp", "cloud"}:
        raise SystemExit("VENAFI_PLATFORM must be mock, tpp, or cloud")

    return Settings(
        platform=platform,
        base_url=_require("VENAFI_BASE_URL").rstrip("/"),
        username=os.getenv("VENAFI_USERNAME", "").strip(),
        password=os.getenv("VENAFI_PASSWORD", "").strip(),
        access_token=os.getenv("VENAFI_ACCESS_TOKEN", "").strip(),
        api_key=os.getenv("VENAFI_API_KEY", "").strip(),
        p12_password=_require("VENAFI_P12_PASSWORD"),
        tls_verify=_bool("VENAFI_TLS_VERIFY", True),
        gcp_project_id=_require("GCP_PROJECT_ID"),
        create_secrets_if_missing=_bool("CREATE_SECRETS_IF_MISSING", False),
        notify_topic=os.getenv("NOTIFY_TOPIC", "").strip(),
        region=os.getenv("GCP_REGION", "us-central1").strip() or "us-central1",
        renew_enabled=_bool("RENEW_ENABLED", True),
        renew_days_before=_int("RENEW_DAYS_BEFORE", 30),
        force_renew=_bool("FORCE_RENEW", False),
        secret_cert_suffix=os.getenv("SECRET_CERT_SUFFIX", "-certificate").strip()
        or "-certificate",
        secret_key_suffix=os.getenv("SECRET_KEY_SUFFIX", "-private-key").strip()
        or "-private-key",
        secret_exclude_prefixes=_csv("SECRET_EXCLUDE_PREFIXES"),
        venafi_dn_label_key=os.getenv("VENAFI_DN_LABEL_KEY", "venafi-dn").strip()
        or "venafi-dn",
        venafi_dn_prefix=os.getenv("VENAFI_DN_PREFIX", r"\VED\Policy\Apps").strip()
        or r"\VED\Policy\Apps",
    )
