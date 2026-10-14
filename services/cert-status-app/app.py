#!/usr/bin/env python3
"""Lab status app that displays the certificate stored in Secret Manager."""

from __future__ import annotations

import os
from datetime import datetime, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from flask import Flask, jsonify, render_template_string
from google.api_core.exceptions import NotFound
from google.cloud import secretmanager

app = Flask(__name__)

PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Certificate status</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 2rem; max-width: 48rem; color: #122; }
    h1 { margin-bottom: 0.25rem; }
    .muted { color: #556; }
    dl { display: grid; grid-template-columns: 11rem 1fr; gap: 0.4rem 1rem; }
    dt { font-weight: 600; }
    dd { margin: 0; word-break: break-all; font-family: ui-monospace, monospace; font-size: 0.92rem; }
    .box { border: 1px solid #ccd; border-radius: 8px; padding: 1rem 1.25rem; margin-top: 1.25rem; background: #f7f9fc; }
    .ok { color: #0a7; font-weight: 600; }
    .err { color: #c33; font-weight: 600; }
    a.btn { display: inline-block; margin-top: 1rem; margin-right: 0.5rem; padding: 0.5rem 0.9rem; background: #153e75; color: #fff; border-radius: 6px; text-decoration: none; }
  </style>
</head>
<body>
  <h1>Certificate status</h1>
  <p class="muted">Lab verification page. TLS terminates at the load balancer. Values below come from Secret Manager (what the sync job last installed).</p>

  <div class="box">
    {% if error %}
      <p class="err">Could not load certificate: {{ error }}</p>
    {% else %}
      <p class="ok">Certificate loaded</p>
      <dl>
        <dt>Subject</dt><dd>{{ cert.subject }}</dd>
        <dt>Issuer</dt><dd>{{ cert.issuer }}</dd>
        <dt>Serial</dt><dd>{{ cert.serial }}</dd>
        <dt>Not before</dt><dd>{{ cert.not_before }}</dd>
        <dt>Not after</dt><dd>{{ cert.not_after }}</dd>
        <dt>Days left</dt><dd>{{ cert.days_left }}</dd>
        <dt>SHA-256</dt><dd>{{ cert.fingerprint }}</dd>
        <dt>Secret</dt><dd>{{ cert.secret_id }}</dd>
        <dt>Secret version</dt><dd>{{ cert.version }}</dd>
        <dt>Generated at</dt><dd>{{ cert.generated_at }}</dd>
      </dl>
      <p class="muted">After a successful renew, Serial, SHA-256, Not after, and Secret version change. Refresh to compare before and after.</p>
    {% endif %}
    <a class="btn" href="/">Refresh</a>
    <a class="btn" href="/api/cert" style="background:#334;">JSON</a>
  </div>
</body>
</html>
"""


def _cert_info() -> dict:
    project = os.environ.get("GCP_PROJECT_ID", "").strip()
    secret_id = os.environ.get("SECRET_CERT_NAME", "").strip()
    if not project:
        raise RuntimeError("GCP_PROJECT_ID is not set")
    if not secret_id:
        raise RuntimeError("SECRET_CERT_NAME is not set")

    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    pem = response.payload.data
    version = response.name.rsplit("/", 1)[-1]

    cert = x509.load_pem_x509_certificate(pem)
    not_after = cert.not_valid_after_utc.astimezone(timezone.utc)
    not_before = cert.not_valid_before_utc.astimezone(timezone.utc)
    days_left = (not_after - datetime.now(timezone.utc)).days
    fingerprint = cert.fingerprint(hashes.SHA256()).hex()

    return {
        "subject": cert.subject.rfc4514_string(),
        "issuer": cert.issuer.rfc4514_string(),
        "serial": format(cert.serial_number, "x"),
        "not_before": not_before.strftime("%Y-%m-%d %H:%M:%SZ"),
        "not_after": not_after.strftime("%Y-%m-%d %H:%M:%SZ"),
        "days_left": days_left,
        "fingerprint": fingerprint,
        "secret_id": secret_id,
        "version": version,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ"),
    }


@app.get("/")
def home():
    try:
        return render_template_string(PAGE, cert=_cert_info(), error=None)
    except NotFound as exc:
        return render_template_string(PAGE, cert=None, error=f"secret not found: {exc}"), 404
    except Exception as exc:  # noqa: BLE001
        return render_template_string(PAGE, cert=None, error=str(exc)[:300]), 500


@app.get("/api/cert")
def api_cert():
    try:
        return jsonify({"status": "ok", "cert": _cert_info()})
    except Exception as exc:  # noqa: BLE001
        return jsonify({"status": "error", "error": str(exc)[:300]}), 500


@app.get("/healthz")
def healthz():
    return "ok", 200
