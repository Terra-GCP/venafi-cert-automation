from __future__ import annotations

from google.api_core.exceptions import AlreadyExists, NotFound
from google.cloud import secretmanager


def upload_secret_version(
    project_id: str,
    secret_id: str,
    payload: bytes,
    create_if_missing: bool = False,
) -> str:
    client = secretmanager.SecretManagerServiceClient()
    parent = f"projects/{project_id}"
    secret_path = f"{parent}/secrets/{secret_id}"

    try:
        client.get_secret(request={"name": secret_path})
    except NotFound:
        if not create_if_missing:
            raise SystemExit(
                f"Secret '{secret_id}' not found in project '{project_id}'."
            )
        try:
            client.create_secret(
                request={
                    "parent": parent,
                    "secret_id": secret_id,
                    "secret": {"replication": {"automatic": {}}},
                }
            )
        except AlreadyExists:
            pass

    response = client.add_secret_version(
        request={
            "parent": secret_path,
            "payload": {"data": payload},
        }
    )
    return response.name


def get_latest_secret_bytes(project_id: str, secret_id: str) -> bytes | None:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    try:
        response = client.access_secret_version(request={"name": name})
    except NotFound:
        return None
    return response.payload.data


def upload_cert_and_key(
    project_id: str,
    secret_cert_name: str,
    secret_key_name: str,
    cert_pem: bytes,
    key_pem: bytes,
    create_if_missing: bool = False,
) -> tuple[str, str]:
    cert_version = upload_secret_version(
        project_id, secret_cert_name, cert_pem, create_if_missing
    )
    key_version = upload_secret_version(
        project_id, secret_key_name, key_pem, create_if_missing
    )
    return cert_version, key_version
