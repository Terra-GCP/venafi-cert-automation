#!/usr/bin/env python3
"""Status page: cert baked at Terraform apply (same PEM as the load balancer)."""

from __future__ import annotations

import os
from datetime import datetime, timezone

from cryptography import x509
from cryptography.x509.oid import NameOID
from flask import Flask, jsonify, render_template_string

app = Flask(__name__)

PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>LB certificate</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 2rem; max-width: 36rem; color: #122; }
    h1 { margin-bottom: 0.35rem; font-size: 1.4rem; }
    .muted { color: #556; font-size: 0.95rem; }
    .box { border: 1px solid #ccd; border-radius: 8px; padding: 1rem 1.2rem; margin-top: 1rem; background: #f7f9fc; }
    dl { display: grid; grid-template-columns: 8rem 1fr; gap: 0.35rem 0.75rem; margin: 0.75rem 0 0; }
    dt { font-weight: 600; color: #445; }
    dd { margin: 0; font-family: ui-monospace, monospace; font-size: 0.95rem; word-break: break-all; }
    .ok { color: #0a7; font-weight: 600; }
    .warn { color: #b86; font-weight: 600; }
    .err { color: #c33; font-weight: 600; }
  </style>
</head>
<body>
  <h1>Load balancer certificate</h1>
  <p class="muted">
    Values are set at Terraform apply (same PEM as Certificate Manager).
    Sync updates Secret Manager only; re-apply Terraform or run the Cloud Build trigger to refresh.
  </p>
  <div class="box">
    {% if error %}
      <p class="err">{{ error }}</p>
    {% else %}
      <p class="{% if cert.days_left <= 30 %}warn{% else %}ok{% endif %}">
        {% if cert.days_left <= 30 %}Near expiry ({{ cert.days_left }} days left){% else %}Valid ({{ cert.days_left }} days left){% endif %}
      </p>
      <dl>
        <dt>CN</dt><dd>{{ cert.cn }}</dd>
        <dt>Expires</dt><dd>{{ cert.not_after }}</dd>
        <dt>Serial</dt><dd>{{ cert.serial }}</dd>
        <dt>SM version</dt><dd>{{ cert.secret_version }} <span class="muted">(at last TF apply)</span></dd>
      </dl>
    {% endif %}
  </div>
</body>
</html>
"""


def _cn(cert: x509.Certificate) -> str:
    attrs = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    return str(attrs[0].value) if attrs else cert.subject.rfc4514_string()


def _cert_info() -> dict:
    pem = os.environ.get("CERT_PEM", "").strip()
    if not pem:
        raise RuntimeError("CERT_PEM is not set; redeploy the example stack with Terraform")
    if "\\n" in pem and "BEGIN" not in pem.split("\n", 1)[0]:
        pem = pem.replace("\\n", "\n")
    cert = x509.load_pem_x509_certificate(pem.encode("utf-8"))
    not_after = cert.not_valid_after_utc.astimezone(timezone.utc)
    days_left = (not_after - datetime.now(timezone.utc)).days
    return {
        "cn": _cn(cert),
        "not_after": not_after.strftime("%Y-%m-%d %H:%M:%SZ"),
        "days_left": days_left,
        "serial": format(cert.serial_number, "x")[-16:],
        "secret_version": os.environ.get("SECRET_VERSION", "").strip() or "unknown",
    }


@app.get("/")
def home():
    try:
        return render_template_string(PAGE, cert=_cert_info(), error=None)
    except Exception as exc:  # noqa: BLE001
        return render_template_string(PAGE, cert=None, error=str(exc)[:300]), 500


@app.get("/api/cert")
def api_cert():
    try:
        return jsonify({"status": "ok", "cert": _cert_info(), "source": "terraform_apply"})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"status": "error", "error": str(exc)[:300]}), 500


@app.get("/healthz")
def healthz():
    return "ok", 200
