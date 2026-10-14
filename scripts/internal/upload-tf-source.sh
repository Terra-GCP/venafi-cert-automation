#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_ID="${PROJECT_ID:-}"
PREFIX="${PREFIX:-venafi-cert}"
BUCKET="${TF_BUCKET:-}"
OBJECT="${TF_SOURCE_OBJECT:-source/lab-https-lb.tgz}"
FORCE_UPLOAD="${FORCE_UPLOAD:-false}"
ARCHIVE="$(mktemp -t lab-https-lb.XXXXXX).tgz"
HASH_OBJECT="${OBJECT}.sha256"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required" >&2
  exit 1
fi
if [[ -z "${BUCKET}" ]]; then
  BUCKET="${PROJECT_ID}-${PREFIX}-tf"
fi

cd "$ROOT"
TAR_ARGS=(
  cloudbuild/lab-https-lb.yaml
  infra/lab-https-lb/apis.tf
  infra/lab-https-lb/backend.tf
  infra/lab-https-lb/certificate.tf
  infra/lab-https-lb/iam.tf
  infra/lab-https-lb/load_balancer.tf
  infra/lab-https-lb/providers.tf
  infra/lab-https-lb/variables.tf
  infra/lab-https-lb/versions.tf
  infra/lab-https-lb/outputs.tf
)
[[ -f infra/lab-https-lb/.terraform.lock.hcl ]] && TAR_ARGS+=(infra/lab-https-lb/.terraform.lock.hcl)

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
