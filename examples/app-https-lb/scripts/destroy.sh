#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${EXAMPLE_ROOT}/../.." && pwd)"
# shellcheck source=../../../scripts/internal/lib.sh
source "${REPO_ROOT}/scripts/internal/lib.sh"
cd "${EXAMPLE_ROOT}"

TFVARS="${EXAMPLE_ROOT}/terraform/terraform.tfvars"
NONINTERACTIVE="${NONINTERACTIVE:-false}"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-}"
APP_PREFIX="${APP_PREFIX:-}"
CERT_NAME="${CERT_NAME:-}"
TF_BUCKET="${TF_BUCKET:-}"

echo ""
echo "Delete example app HTTPS LB stack"
echo "  Env and terraform.tfvars values are reused; only missing values are prompted"
echo ""

resolve_str PROJECT_ID "GCP project ID" "" "project_id" "${TFVARS}"
resolve_str REGION "GCP region" "us-central1" "region" "${TFVARS}"
resolve_str APP_PREFIX "Example stack name prefix" "venafi-cert-app" "name_prefix" "${TFVARS}"

if [[ -z "${CERT_NAME}" ]] && tfvar_has "${TFVARS}" "secret_cert_name"; then
  CERT_NAME="$(tfvar_get "${TFVARS}" "secret_cert_name")"
  CERT_NAME="${CERT_NAME%-certificate}"
  echo "  CERT_NAME=${CERT_NAME} (from terraform.tfvars)" >&2
fi
resolve_str CERT_NAME "Cert logical name" "app-tls"

if [[ -z "${TF_BUCKET}" ]] && tfvar_has "${TFVARS}" "tf_state_bucket"; then
  TF_BUCKET="$(tfvar_get "${TFVARS}" "tf_state_bucket")"
  echo "  TF_BUCKET=${TF_BUCKET} (from terraform.tfvars)" >&2
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

if [[ "${NONINTERACTIVE}" != "true" ]]; then
  ask_yn "Are you sure?" "y" || { echo "Cancelled."; exit 0; }
fi

SECRET_CERT="${CERT_NAME}-certificate"
SECRET_KEY="${CERT_NAME}-private-key"
TF_BUCKET="${TF_BUCKET:-${PROJECT_ID}-${APP_PREFIX}-tf}"
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Destroying example stack..."
cat > "${TFVARS}" <<EOF
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

gcloud secrets delete "${SECRET_CERT}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud secrets delete "${SECRET_KEY}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo "Done. Core automation was not touched."
