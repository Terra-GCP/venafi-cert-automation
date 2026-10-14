from __future__ import annotations

import time

import google.auth
import google.auth.transport.requests
import requests


def run_trigger_and_wait(
    *,
    project_id: str,
    location: str,
    trigger_id: str,
    mode: str = "apply",
    poll_seconds: int = 15,
    timeout_seconds: int = 1500,
) -> str:
    """Run a Cloud Build trigger and wait until the build finishes.

    Note: regional triggers.run does not accept a substitutions field in the
    request body. The trigger default is _MODE=apply. For plan-only, use:
      gcloud builds triggers run TRIGGER --region=REGION --substitutions=_MODE=plan
    """
    if mode != "apply":
        raise RuntimeError(
            "Job only runs trigger with default _MODE=apply. "
            "For plan-only use: gcloud builds triggers run "
            f"{trigger_id} --region={location} --substitutions=_MODE=plan"
        )

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
    }

    run_url = (
        f"https://cloudbuild.googleapis.com/v1/projects/{project_id}"
        f"/locations/{location}/triggers/{trigger_id}:run"
    )
    # Empty body is valid; do not send substitutions (API rejects that field here).
    resp = requests.post(run_url, headers=headers, json={}, timeout=60)
    if resp.status_code >= 300:
        raise RuntimeError(f"Trigger run failed ({resp.status_code}): {resp.text[:800]}")

    payload = resp.json()
    metadata = payload.get("metadata", {})
    build = metadata.get("build", {}) if isinstance(metadata, dict) else {}
    build_id = build.get("id") or payload.get("id") or ""
    if not build_id:
        raise RuntimeError(f"Trigger run response missing build id: {str(payload)[:500]}")

    print(f"Cloud Build trigger started: {trigger_id} build={build_id}")

    get_url = (
        f"https://cloudbuild.googleapis.com/v1/projects/{project_id}"
        f"/locations/{location}/builds/{build_id}"
    )
    global_get_url = f"https://cloudbuild.googleapis.com/v1/projects/{project_id}/builds/{build_id}"

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        status_resp = requests.get(get_url, headers=headers, timeout=60)
        if status_resp.status_code == 404:
            status_resp = requests.get(global_get_url, headers=headers, timeout=60)
        if status_resp.status_code >= 300:
            raise RuntimeError(
                f"Build poll failed ({status_resp.status_code}): {status_resp.text[:500]}"
            )
        status = status_resp.json().get("status", "UNKNOWN")
        if status in {"SUCCESS", "FAILURE", "INTERNAL_ERROR", "TIMEOUT", "CANCELLED", "EXPIRED"}:
            if status != "SUCCESS":
                log_url = status_resp.json().get("logUrl", "")
                raise RuntimeError(f"Cloud Build {build_id} ended with {status}. Logs: {log_url}")
            print(f"Cloud Build succeeded: {build_id}")
            return build_id
        time.sleep(poll_seconds)

    raise RuntimeError(f"Cloud Build {build_id} timed out after {timeout_seconds}s")
