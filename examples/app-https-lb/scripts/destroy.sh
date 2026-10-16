#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${EXAMPLE_ROOT}/../.." && pwd)"
# shellcheck source=../../../scripts/internal/lib.sh
source "${REPO_ROOT}/scripts/internal/lib.sh"
cd "${EXAMPLE_ROOT}"

NONINTERACTIVE="${NONINTERACTIVE:-false}"

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  PROJECT_ID="${PROJECT_ID:-}"
  REGION="${REGION:-us-central1}"
  APP_PREFIX="${APP_PREFIX:-venafi-cert-app}"
  CERT_NAME="${CERT_NAME:-app-tls}"
  if [[ -z "${PROJECT_ID}" ]]; then
    echo "PROJECT_ID is required when NONINTERACTIVE=true" >&2
    exit 1
  fi
else
  echo ""
  echo "Delete example app HTTPS LB stack"
  echo ""
  PROJECT_ID="$(ask "GCP project ID" "${PROJECT_ID:-}")"
  REGION="$(ask "GCP region" "${REGION:-us-central1}")"
  APP_PREFIX="$(ask "Example stack name prefix" "${APP_PREFIX:-venafi-cert-app}")"
  CERT_NAME="$(ask "Cert logical name" "${CERT_NAME:-app-tls}")"
  ask_yn "Are you sure?" "y" || { echo "Cancelled."; exit 0; }
fi

SECRET_CERT="${CERT_NAME}-certificate"
SECRET_KEY="${CERT_NAME}-private-key"
TF_BUCKET="${PROJECT_ID}-${APP_PREFIX}-tf"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Destroying example stack..."
cat > terraform/terraform.tfvars <<EOF
project_id         = "${PROJECT_ID}"
region             = "${REGION}"
name_prefix        = "${APP_PREFIX}"
secret_cert_name   = "${SECRET_CERT}"
secret_key_name    = "${SECRET_KEY}"
status_app_image   = "placeholder"
tf_state_bucket    = "${TF_BUCKET}"
EOF

if gsutil ls -b "gs://${TF_BUCKET}" >/dev/null 2>&1; then
  cd terraform
  terraform init -input=false -reconfigure \
    -backend-config="bucket=${TF_BUCKET}" \
    -backend-config="prefix=app-https-lb" >/dev/null || true
  terraform destroy -input=false -auto-approve -refresh=false || \
    terraform destroy -input=false -auto-approve || true
  cd "${EXAMPLE_ROOT}"
fi

p="${APP_PREFIX}"
gcloud compute forwarding-rules delete "${p}-https" --global --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud compute target-https-proxies delete "${p}-https-proxy" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud compute url-maps delete "${p}-urlmap" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud compute backend-services delete "${p}-backend" --global --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud compute network-endpoint-groups delete "${p}-neg" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud compute addresses delete "${p}-ip" --global --project="${PROJECT_ID}" --quiet 2>/dev/null || true
for e in $(gcloud certificate-manager maps entries list --map="${p}-map" --project="${PROJECT_ID}" --format='value(name)' 2>/dev/null || true); do
  gcloud certificate-manager maps entries delete "$e" --map="${p}-map" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done
gcloud certificate-manager maps delete "${p}-map" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud run services delete "${p}-app" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud iam service-accounts delete "${p}-app@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud builds triggers delete "${p}-https-lb" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${p}-tf-apply" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud artifacts repositories delete "${p}" --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gsutil -m rm -r "gs://${TF_BUCKET}" >/dev/null 2>&1 || true

# Secrets were created by the example seed script (not Terraform).
gcloud secrets delete "${SECRET_CERT}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud secrets delete "${SECRET_KEY}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo "Done. Core automation was not touched."
