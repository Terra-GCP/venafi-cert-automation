#!/usr/bin/env python3
"""Seed Secret Manager with near-expiry certificates for first-run renewal demos.

Lab deploy leaves these as secret version 1 so the status page starts "due soon".
A later sync / scheduler run renews them (version 2+) without needing force renew.
"""

from __future__ import annotations

import argparse
import datetime as dt

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from google.cloud import secretmanager


def _near_expiry_pair(cn: str, days_until_expiry: int) -> tuple[bytes, bytes]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Venafi Cert Automation"),
            x509.NameAttribute(NameOID.COMMON_NAME, cn),
        ]
    )
    now = dt.datetime.now(dt.timezone.utc)
    # Still valid for HTTPS, but inside the sync renew window (default 30 days).
    not_after = now + dt.timedelta(days=days_until_expiry)
    not_before = not_after - dt.timedelta(days=90)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(cn)]), critical=False)
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM)
    key_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return cert_pem, key_pem


def _add_version(client: secretmanager.SecretManagerServiceClient, project: str, secret_id: str, data: bytes) -> str:
    parent = f"projects/{project}/secrets/{secret_id}"
    response = client.add_secret_version(
        request={"parent": parent, "payload": {"data": data}}
    )
    return response.name.rsplit("/", 1)[-1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-id", required=True)
    parser.add_argument(
        "--specs",
        required=True,
        help="Comma-separated cert_name:cn pairs, e.g. app-tls:app.example.local,edge-tls:edge.example.local",
    )
    parser.add_argument(
        "--days-until-expiry",
        type=int,
        default=7,
        help="Days until the seeded cert expires (must be <= renew_days_before so sync renews without force)",
    )
    args = parser.parse_args()

    if args.days_until_expiry < 1:
        raise SystemExit("--days-until-expiry must be >= 1 (seed a still-valid near-expiry cert for the lab LB)")

    client = secretmanager.SecretManagerServiceClient()
    for spec in args.specs.split(","):
        cert_name, cn = spec.strip().split(":", 1)
        cert_pem, key_pem = _near_expiry_pair(cn.strip(), args.days_until_expiry)
        cert_secret = f"{cert_name.strip()}-certificate"
        key_secret = f"{cert_name.strip()}-private-key"
        cert_ver = _add_version(client, args.project_id, cert_secret, cert_pem)
        key_ver = _add_version(client, args.project_id, key_secret, key_pem)
        print(
            f"Seeded near-expiry cert '{cert_name.strip()}' CN={cn.strip()} "
            f"({args.days_until_expiry}d left) cert_v={cert_ver} key_v={key_ver}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
