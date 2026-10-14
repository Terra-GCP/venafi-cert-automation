#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
PREFIX="${PREFIX:-venafi-cert}"
NONINTERACTIVE="${NONINTERACTIVE:-false}"
FORCE="${FORCE:-false}"

if [[ "${NONINTERACTIVE}" != "true" ]]; then
  PROJECT_ID="$(ask "GCP project ID" "${PROJECT_ID}")"
  REGION="$(ask "GCP region" "${REGION}")"
  PREFIX="$(ask "Resource name prefix" "${PREFIX}")"
  echo ""
  echo "Force renew requests a new certificate even when the current one is still valid."
  ask_yn "Force renew now?" "n" && FORCE=true
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

JOB_NAME="${PREFIX}-sync"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Running sync job ${JOB_NAME}..."
if [[ "${FORCE}" == "true" ]]; then
  # Override for this execution only (no Terraform change required).
  gcloud run jobs execute "${JOB_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --update-env-vars=FORCE_RENEW=true \
    --wait
else
  gcloud run jobs execute "${JOB_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --wait
fi

EXEC="$(gcloud run jobs executions list --job="${JOB_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --limit=1 --format='value(name)')"
echo ""
echo "Job output:"
gcloud logging read \
  "resource.labels.job_name=\"${JOB_NAME}\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXEC}\"" \
  --project="${PROJECT_ID}" --limit=20 --format='value(textPayload)' 2>/dev/null | sed '/^$/d' | head -30
echo ""
