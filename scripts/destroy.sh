#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

TFVARS="${ROOT}/terraform/terraform.tfvars"
NONINTERACTIVE="${NONINTERACTIVE:-false}"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-}"
PREFIX="${PREFIX:-}"

echo ""
echo "Delete Venafi certificate automation (core only)"
echo "  Env and terraform.tfvars values are reused; only missing values are prompted"
echo "  Example stacks are separate: examples/*/scripts/destroy.sh"
echo ""

resolve_str PROJECT_ID "GCP project ID" "" "project_id" "${TFVARS}"
resolve_str REGION "GCP region" "us-central1" "region" "${TFVARS}"
resolve_str PREFIX "Resource name prefix" "venafi-cert" "name_prefix" "${TFVARS}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required (set project_id in terraform.tfvars, PROJECT_ID=…, or answer the prompt)" >&2
  exit 1
fi

if [[ "${NONINTERACTIVE}" != "true" ]]; then
  ask_yn "Are you sure?" "y" || { echo "Cancelled."; exit 0; }
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Deleting core automation..."
if [[ ! -f "${TFVARS}" ]]; then
  cat > "${TFVARS}" <<EOF
project_id  = "${PROJECT_ID}"
region      = "${REGION}"
name_prefix = "${PREFIX}"
enable_mock = true
EOF
fi

cd terraform
terraform init -input=false -reconfigure >/dev/null || true
if [[ -f terraform.tfstate ]] && [[ "$(terraform state list 2>/dev/null | wc -l | tr -d ' ')" != "0" ]]; then
  terraform destroy -input=false -auto-approve || true
fi
cd "$ROOT"

echo "Cleaning leftover named resources (prefix=${PREFIX})..."
gcloud run jobs delete "${PREFIX}-sync" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud run services delete "${PREFIX}-mock" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud scheduler jobs delete "${PREFIX}-daily" --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${PREFIX}-events" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud artifacts repositories delete "${PREFIX}" --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

for sa in sync mock sched; do
  gcloud iam service-accounts delete "${PREFIX}-${sa}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

for secret in \
  "${PREFIX}-venafi-username" \
  "${PREFIX}-venafi-password" \
  "${PREFIX}-venafi-p12-password"
do
  gcloud secrets delete "${secret}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

while IFS= read -r policy; do
  [[ -z "${policy}" ]] && continue
  gcloud monitoring policies delete "${policy}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done < <(
  gcloud monitoring policies list --project="${PROJECT_ID}" \
    --filter="displayName:${PREFIX}" --format='value(name)' 2>/dev/null || true
)
while IFS= read -r ch; do
  [[ -z "${ch}" ]] && continue
  gcloud monitoring channels delete "${ch}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done < <(
  gcloud monitoring channels list --project="${PROJECT_ID}" \
    --filter="displayName:${PREFIX}" --format='value(name)' 2>/dev/null || true
)

echo "Done (core only)."
echo "Examples (if deployed): examples/app-https-lb/scripts/destroy.sh and examples/edge-https-lb/scripts/destroy.sh"
