#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

NONINTERACTIVE="${NONINTERACTIVE:-false}"
DESTROY_EXAMPLES="${DESTROY_EXAMPLES:-false}"

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  PROJECT_ID="${PROJECT_ID:-}"
  REGION="${REGION:-us-central1}"
  PREFIX="${PREFIX:-venafi-cert}"
  if [[ -z "${PROJECT_ID}" ]]; then
    echo "PROJECT_ID is required when NONINTERACTIVE=true" >&2
    exit 1
  fi
else
  echo ""
  echo "Delete Venafi certificate automation"
  echo ""
  PROJECT_ID="$(ask "GCP project ID" "${PROJECT_ID:-}")"
  REGION="$(ask "GCP region" "${REGION:-us-central1}")"
  PREFIX="$(ask "Resource name prefix" "${PREFIX:-venafi-cert}")"
  if ask_yn "Also destroy example stacks (app-https-lb / edge-https-lb)?" "y"; then
    DESTROY_EXAMPLES=true
  fi
  ask_yn "Are you sure?" "y" || { echo "Cancelled."; exit 0; }
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

if [[ "${DESTROY_EXAMPLES}" == "true" ]]; then
  echo "Destroying example stacks..."
  NONINTERACTIVE=true PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" \
    APP_PREFIX=venafi-cert-app CERT_NAME=app-tls \
    "${ROOT}/examples/app-https-lb/scripts/destroy.sh" || true
  NONINTERACTIVE=true PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" \
    APP_PREFIX=venafi-cert-edge CERT_NAME=edge-tls \
    "${ROOT}/examples/edge-https-lb/scripts/destroy.sh" || true
fi

echo "Deleting core automation..."
if [[ ! -f terraform/terraform.tfvars ]]; then
  cat > terraform/terraform.tfvars <<EOF
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

# Venafi creds + common example TLS secrets created outside Terraform.
for secret in \
  "${PREFIX}-venafi-username" \
  "${PREFIX}-venafi-password" \
  "${PREFIX}-venafi-p12-password" \
  app-tls-certificate \
  app-tls-private-key \
  edge-tls-certificate \
  edge-tls-private-key
do
  gcloud secrets delete "${secret}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

# Monitoring leftovers matching this prefix only.
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

echo "Done."
if [[ "${DESTROY_EXAMPLES}" != "true" ]]; then
  echo "Example stacks were not destroyed. If still present:"
  echo "  examples/app-https-lb/scripts/destroy.sh"
  echo "  examples/edge-https-lb/scripts/destroy.sh"
  echo "Or re-run with DESTROY_EXAMPLES=true"
fi
