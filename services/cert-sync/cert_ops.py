from __future__ import annotations

from dataclasses import dataclass
from datetime import timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12


@dataclass(frozen=True)
class SplitResult:
    cert_pem: bytes
    key_pem: bytes
    subject: str
    not_after: str
    key_matches: bool


def split_pkcs12(package_path: Path, password: str) -> SplitResult:
    raw = package_path.read_bytes()
    try:
        private_key, certificate, additional = pkcs12.load_key_and_certificates(
            raw, password.encode("utf-8")
        )
    except Exception as exc:
        raise SystemExit(
            f"Failed to decrypt PKCS#12. Check VENAFI_P12_PASSWORD. Detail: {exc}"
        ) from exc

    if private_key is None or certificate is None:
        raise SystemExit("PKCS#12 did not contain both a private key and a leaf certificate")

    chain = [certificate, *(additional or [])]
    cert_pem = b"".join(
        c.public_bytes(serialization.Encoding.PEM) for c in chain if c is not None
    )
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )

    key_matches = _key_matches_cert(private_key, certificate)
    not_after = certificate.not_valid_after_utc.astimezone(timezone.utc).strftime(
        "%Y-%m-%d %H:%M:%SZ"
    )
    subject = certificate.subject.rfc4514_string()

    return SplitResult(
        cert_pem=cert_pem,
        key_pem=key_pem,
        subject=subject,
        not_after=not_after,
        key_matches=key_matches,
    )


def _key_matches_cert(private_key, certificate: x509.Certificate) -> bool:
    pub_from_key = private_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    pub_from_cert = certificate.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return pub_from_key == pub_from_cert
