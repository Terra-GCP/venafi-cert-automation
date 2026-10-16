from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from cryptography import x509
from cryptography.x509.oid import NameOID
from google.api_core.exceptions import NotFound
from google.cloud import secretmanager

from secret_manager import get_latest_secret_bytes


@dataclass(frozen=True)
class DiscoveredCert:
    name: str
    secret_cert_name: str
    secret_key_name: str
    common_name: str
    certificate_dn: str | None
    days_left: int | None
    expiry: str | None


def _cn_from_pem(cert_pem: bytes) -> str:
    cert = x509.load_pem_x509_certificate(cert_pem)
    attrs = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    if attrs:
        return str(attrs[0].value)
    # Fall back to first SAN DNS name
    try:
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        dns_names = san.value.get_values_for_type(x509.DNSName)
        if dns_names:
            return str(dns_names[0])
    except x509.ExtensionNotFound:
        pass
    raise ValueError("certificate has no Common Name or DNS SAN")


def _days_left_from_pem(cert_pem: bytes) -> tuple[int, str]:
    cert = x509.load_pem_x509_certificate(cert_pem)
    valid_to = cert.not_valid_after_utc.astimezone(timezone.utc)
    days_left = (valid_to - datetime.now(timezone.utc)).days
    return days_left, valid_to.strftime("%Y-%m-%d %H:%M:%SZ")


def _looks_like_pem_cert(data: bytes) -> bool:
    text = data[:200].decode("utf-8", errors="ignore")
    return "BEGIN CERTIFICATE" in text


def discover_project_certs(
    project_id: str,
    *,
    cert_suffix: str = "-certificate",
    key_suffix: str = "-private-key",
    exclude_prefixes: tuple[str, ...] = (),
    dn_label_key: str = "venafi-dn",
) -> list[DiscoveredCert]:
    """Find PEM cert secrets in Secret Manager and pair each with a private-key secret."""
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{project_id}"
    found: list[DiscoveredCert] = []

    for secret in client.list_secrets(request={"parent": parent}):
        secret_id = secret.name.rsplit("/", 1)[-1]
        if not secret_id.endswith(cert_suffix):
            continue
        if any(secret_id.startswith(p) for p in exclude_prefixes if p):
            continue

        name = secret_id[: -len(cert_suffix)]
        if not name:
            continue
        key_id = f"{name}{key_suffix}"
        key_path = f"{parent}/secrets/{key_id}"
        try:
            client.get_secret(request={"name": key_path})
        except NotFound:
            print(f"Skip {secret_id}: paired secret '{key_id}' not found")
            continue

        annotations = dict(secret.annotations or {})
        labels = dict(secret.labels or {})
        preferred_dn = (
            (annotations.get(dn_label_key) or labels.get(dn_label_key) or "").strip() or None
        )

        pem = get_latest_secret_bytes(project_id, secret_id)
        if not pem:
            print(f"Skip {secret_id}: no enabled versions")
            continue
        if not _looks_like_pem_cert(pem):
            print(f"Skip {secret_id}: latest version is not a PEM certificate")
            continue

        try:
            cn = _cn_from_pem(pem)
            days_left, expiry = _days_left_from_pem(pem)
        except Exception as exc:
            print(f"Skip {secret_id}: cannot parse PEM ({exc})")
            continue

        found.append(
            DiscoveredCert(
                name=name,
                secret_cert_name=secret_id,
                secret_key_name=key_id,
                common_name=cn,
                certificate_dn=preferred_dn,
                days_left=days_left,
                expiry=expiry,
            )
        )

    found.sort(key=lambda c: c.name)
    return found
