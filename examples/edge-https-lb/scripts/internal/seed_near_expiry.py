#!/usr/bin/env python3
"""Create and seed near-expiry TLS material in Secret Manager for example stacks."""

from __future__ import annotations

import argparse
import datetime as dt

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from google.api_core.exceptions import AlreadyExists, NotFound
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


def _ensure_secret(
    client: secretmanager.SecretManagerServiceClient,
    project: str,
    secret_id: str,
    *,
    labels: dict[str, str] | None = None,
    annotations: dict[str, str] | None = None,
) -> None:
    parent = f"projects/{project}"
    name = f"{parent}/secrets/{secret_id}"
    try:
        secret = client.get_secret(request={"name": name})
        paths: list[str] = []
        body: dict = {"name": name}
        if labels:
            merged_labels = dict(secret.labels or {})
            merged_labels.update(labels)
            body["labels"] = merged_labels
            paths.append("labels")
        if annotations:
            merged_ann = dict(secret.annotations or {})
            merged_ann.update(annotations)
            body["annotations"] = merged_ann
            paths.append("annotations")
        if paths:
            client.update_secret(
                request={"secret": body, "update_mask": {"paths": paths}}
            )
    except NotFound:
        try:
            client.create_secret(
                request={
                    "parent": parent,
                    "secret_id": secret_id,
                    "secret": {
                        "replication": {"automatic": {}},
                        "labels": labels or {},
                        "annotations": annotations or {},
                    },
                }
            )
        except AlreadyExists:
            pass


def _add_version(
    client: secretmanager.SecretManagerServiceClient,
    project: str,
    secret_id: str,
    data: bytes,
) -> str:
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
        help="Comma-separated cert_name:cn pairs, e.g. app-tls:app.example.local",
    )
    parser.add_argument("--days-until-expiry", type=int, default=7)
    parser.add_argument("--venafi-dn-prefix", default=r"\VED\Policy\Apps")
    args = parser.parse_args()

    if args.days_until_expiry < 1:
        raise SystemExit("--days-until-expiry must be >= 1")

    client = secretmanager.SecretManagerServiceClient()
    for spec in args.specs.split(","):
        cert_name, cn = spec.strip().split(":", 1)
        cert_name = cert_name.strip()
        cn = cn.strip()
        cert_pem, key_pem = _near_expiry_pair(cn, args.days_until_expiry)
        cert_secret = f"{cert_name}-certificate"
        key_secret = f"{cert_name}-private-key"
        venafi_dn = f"{args.venafi_dn_prefix.rstrip(chr(92))}\\{cn}"
        _ensure_secret(
            client,
            args.project_id,
            cert_secret,
            labels={"managed-by": "venafi-cert-example"},
            annotations={"venafi-dn": venafi_dn},
        )
        _ensure_secret(
            client,
            args.project_id,
            key_secret,
            labels={"managed-by": "venafi-cert-example"},
        )
        cert_ver = _add_version(client, args.project_id, cert_secret, cert_pem)
        key_ver = _add_version(client, args.project_id, key_secret, key_pem)
        print(
            f"Seeded '{cert_name}' CN={cn} ({args.days_until_expiry}d left) "
            f"DN={venafi_dn} cert_v={cert_ver} key_v={key_ver}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
