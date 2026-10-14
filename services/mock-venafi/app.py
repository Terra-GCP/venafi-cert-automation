from __future__ import annotations

import datetime as dt
import io
import os

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID
from flask import Flask, jsonify, request, send_file

app = Flask(__name__)

MOCK_USER = os.getenv("MOCK_VENAFI_USER", "mock-user")
MOCK_PASSWORD = os.getenv("MOCK_VENAFI_PASSWORD", "mock-password")
DEFAULT_P12_PASSWORD = os.getenv("MOCK_P12_PASSWORD", "changeit")
CERT_CN = os.getenv("MOCK_CERT_CN", "app.example.local")
DEFAULT_DN = os.getenv("MOCK_CERT_DN", r"\VED\Policy\Apps\app.example.local")
INITIAL_DAYS_LEFT = int(os.getenv("MOCK_INITIAL_DAYS_LEFT", "7"))
RENEW_VALIDITY_DAYS = int(os.getenv("MOCK_RENEW_VALIDITY_DAYS", "90"))
TOKEN = "mock-access-token"

_STORE: dict[str, dict] = {}


def _auth_ok() -> bool:
    return request.headers.get("Authorization", "") == f"Bearer {TOKEN}"


def _issue_bundle(cn: str, p12_password: str, days_valid: int) -> tuple[bytes, dt.datetime]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Venafi Cert Automation"),
            x509.NameAttribute(NameOID.COMMON_NAME, cn),
        ]
    )
    now = dt.datetime.now(dt.timezone.utc)
    if days_valid >= 0:
        not_before = now - dt.timedelta(minutes=1)
        valid_to = now + dt.timedelta(days=days_valid)
    else:
        valid_to = now + dt.timedelta(days=days_valid)
        not_before = valid_to - dt.timedelta(days=90)

    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before)
        .not_valid_after(valid_to)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(cn)]), critical=False)
        .sign(key, hashes.SHA256())
    )
    payload = pkcs12.serialize_key_and_certificates(
        name=cn.encode("utf-8"),
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(p12_password.encode("utf-8")),
    )
    return payload, valid_to


def _ensure(dn: str, password: str) -> dict:
    if dn not in _STORE:
        p12, valid_to = _issue_bundle(CERT_CN, password, INITIAL_DAYS_LEFT)
        _STORE[dn] = {
            "p12": p12,
            "valid_to": valid_to,
            "cn": CERT_CN,
            "password": password,
        }
    return _STORE[dn]


@app.get("/healthz")
def healthz():
    return {"status": "ok", "certs": len(_STORE)}


@app.post("/vedauth/authorize/oauth")
@app.post("/vedauth/authorize/integrated")
def authorize():
    data = request.get_json(silent=True) or {}
    form = request.form or {}
    username = data.get("username") or form.get("username")
    password = data.get("password") or form.get("password")
    if username != MOCK_USER or password != MOCK_PASSWORD:
        return jsonify({"error": "invalid_credentials"}), 401
    return jsonify({"access_token": TOKEN, "expires_in": 3600})


@app.get("/vedsdk/Certificates")
def list_certificates():
    if not _auth_ok():
        return jsonify({"error": "unauthorized"}), 401
    password = DEFAULT_P12_PASSWORD
    entry = _ensure(DEFAULT_DN, password)
    return jsonify(
        {
            "Certificates": [
                {
                    "DN": DEFAULT_DN,
                    "Name": entry["cn"],
                    "CN": entry["cn"],
                    "ValidTo": entry["valid_to"].strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
            ]
        }
    )


@app.post("/vedsdk/Certificates/Renew")
def renew_certificate():
    if not _auth_ok():
        return jsonify({"error": "unauthorized"}), 401
    data = request.get_json(silent=True) or {}
    dn = data.get("CertificateDN") or request.args.get("CertificateDN") or DEFAULT_DN
    password = data.get("Password") or DEFAULT_P12_PASSWORD
    p12, valid_to = _issue_bundle(CERT_CN, password, RENEW_VALIDITY_DAYS)
    _STORE[dn] = {
        "p12": p12,
        "valid_to": valid_to,
        "cn": CERT_CN,
        "password": password,
    }
    return jsonify(
        {
            "Success": True,
            "CertificateDN": dn,
            "ValidTo": valid_to.strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
    )


@app.get("/vedsdk/Certificates/Retrieve")
def retrieve_certificate():
    if not _auth_ok():
        return jsonify({"error": "unauthorized"}), 401

    password = request.args.get("Password") or DEFAULT_P12_PASSWORD
    dn = request.args.get("CertificateDN") or DEFAULT_DN
    fmt = request.args.get("Format", "")
    if "PKCS" not in fmt:
        return jsonify({"error": "only PKCS #12 is supported by this mock"}), 400

    entry = _ensure(dn, password)
    if entry["password"] != password:
        p12, valid_to = _issue_bundle(entry["cn"], password, INITIAL_DAYS_LEFT)
        entry = {
            "p12": p12,
            "valid_to": valid_to,
            "cn": entry["cn"],
            "password": password,
        }
        _STORE[dn] = entry

    return send_file(
        io.BytesIO(entry["p12"]),
        mimetype="application/x-pkcs12",
        as_attachment=True,
        download_name="cert.p12",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
