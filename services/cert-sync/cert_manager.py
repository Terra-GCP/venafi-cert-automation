from __future__ import annotations

import time
import uuid

import google.auth
import google.auth.transport.requests
import requests


def _token() -> str:
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    return credentials.token


def rotate_certificate(
    project_id: str,
    map_name: str,
    entry_name: str,
    cert_name_prefix: str,
    pem_certificate: str,
    pem_private_key: str,
) -> str:
    token = _token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    cert_id = f"{cert_name_prefix}-{uuid.uuid4().hex[:8]}"
    parent = f"https://certificatemanager.googleapis.com/v1/projects/{project_id}/locations/global"

    create_url = f"{parent}/certificates?certificateId={cert_id}"
    body = {
        "description": "cert-sync",
        "selfManaged": {
            "pemCertificate": pem_certificate,
            "pemPrivateKey": pem_private_key,
        },
    }
    response = requests.post(create_url, headers=headers, json=body, timeout=120)
    if response.status_code >= 400:
        raise SystemExit(
            f"Certificate Manager create failed: HTTP {response.status_code}: {response.text[:400]}"
        )

    cert_resource = (
        f"projects/{project_id}/locations/global/certificates/{cert_id}"
    )
    time.sleep(5)

    entry_url = f"{parent}/certificateMaps/{map_name}/certificateMapEntries/{entry_name}"
    patch = {"certificates": [cert_resource]}
    patch_resp = requests.patch(
        f"{entry_url}?updateMask=certificates",
        headers=headers,
        json=patch,
        timeout=120,
    )
    if patch_resp.status_code >= 400:
        raise SystemExit(
            f"Certificate map entry update failed: HTTP {patch_resp.status_code}: {patch_resp.text[:400]}"
        )

    return cert_resource
