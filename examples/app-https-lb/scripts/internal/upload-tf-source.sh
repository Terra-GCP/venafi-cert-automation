#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ID="${PROJECT_ID:-}"
BUCKET="${TF_BUCKET:-}"
OBJECT="${TF_SOURCE_OBJECT:-source/app-https-lb.tgz}"
FORCE_UPLOAD="${FORCE_UPLOAD:-false}"
ARCHIVE="$(mktemp -t app-https-lb.XXXXXX).tgz"
HASH_OBJECT="${OBJECT}.sha256"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required" >&2
  exit 1
fi
if [[ -z "${BUCKET}" ]]; then
  echo "TF_BUCKET is required" >&2
  exit 1
fi

cd "${EXAMPLE_ROOT}"
TAR_ARGS=(
  cloudbuild/apply-lb.yaml
  terraform/apis.tf
  terraform/backend.tf
  terraform/certificate.tf
  terraform/iam.tf
  terraform/load_balancer.tf
  terraform/providers.tf
  terraform/variables.tf
  terraform/versions.tf
  terraform/outputs.tf
  terraform/trigger.tf
)
[[ -f terraform/.terraform.lock.hcl ]] && TAR_ARGS+=(terraform/.terraform.lock.hcl)

tar -czf "${ARCHIVE}" "${TAR_ARGS[@]}"
LOCAL_HASH="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"

if [[ "${FORCE_UPLOAD}" != "true" ]] && gsutil -q stat "gs://${BUCKET}/${HASH_OBJECT}" 2>/dev/null; then
  REMOTE_HASH="$(gsutil cat "gs://${BUCKET}/${HASH_OBJECT}" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "${REMOTE_HASH}" == "${LOCAL_HASH}" ]] && gsutil -q stat "gs://${BUCKET}/${OBJECT}" 2>/dev/null; then
    rm -f "${ARCHIVE}"
    echo "TF source unchanged, skip upload"
    exit 0
  fi
fi

gsutil cp "${ARCHIVE}" "gs://${BUCKET}/${OBJECT}"
printf '%s' "${LOCAL_HASH}" | gsutil cp - "gs://${BUCKET}/${HASH_OBJECT}"
rm -f "${ARCHIVE}"
echo "Uploaded gs://${BUCKET}/${OBJECT}"
