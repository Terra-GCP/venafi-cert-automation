#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

NONINTERACTIVE="${NONINTERACTIVE:-false}"

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  PROJECT_ID="${PROJECT_ID:-}"
  REGION="${REGION:-us-central1}"
  PREFIX="${PREFIX:-venafi-cert}"
  LAB_ONLY="${LAB_ONLY:-false}"
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
  LAB_ONLY=false
  echo "  y = everything (core automation + lab kit)"
  echo "  n = lab HTTPS verification stack only"
  ask_yn "Delete everything?" "y" || LAB_ONLY=true
  ask_yn "Are you sure?" "y" || { echo "Cancelled."; exit 0; }
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

LAB_PREFIX="${PREFIX}-lab"
# Legacy name from earlier builds
LEGACY_PREFIX="${PREFIX}-sample"
TF_BUCKET="${PROJECT_ID}-${PREFIX}-tf"
gcloud config set project "${PROJECT_ID}" >/dev/null

destroy_lab_prefix() {
  local p="$1"
  echo "Deleting lab / verification stack (prefix=${p})..."
  cat > infra/lab-https-lb/terraform.tfvars <<EOF
project_id         = "${PROJECT_ID}"
region             = "${REGION}"
name_prefix        = "${p}"
secret_cert_name   = "placeholder-certificate"
secret_key_name    = "placeholder-private-key"
status_app_image   = "placeholder"
EOF
  if gsutil ls "gs://${TF_BUCKET}/lab-https-lb/" >/dev/null 2>&1 || gsutil ls "gs://${TF_BUCKET}/sample-https-lb/" >/dev/null 2>&1; then
    cd infra/lab-https-lb
    terraform init -input=false -reconfigure \
      -backend-config="bucket=${TF_BUCKET}" \
      -backend-config="prefix=lab-https-lb" >/dev/null 2>&1 || \
    terraform init -input=false -reconfigure \
      -backend-config="bucket=${TF_BUCKET}" \
      -backend-config="prefix=sample-https-lb" >/dev/null || true
    terraform destroy -input=false -auto-approve || true
    cd "$ROOT"
    gsutil -m rm -r "gs://${TF_BUCKET}/lab-https-lb" >/dev/null 2>&1 || true
    gsutil -m rm -r "gs://${TF_BUCKET}/sample-https-lb" >/dev/null 2>&1 || true
  fi

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
  for c in $(gcloud certificate-manager certificates list --project="${PROJECT_ID}" --format='value(name)' 2>/dev/null | grep -E "^(${p}-|demo-cert-|app-tls-)" || true); do
    gcloud certificate-manager certificates delete "$c" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  done
  gcloud run services delete "${p}-app" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  gcloud run services delete "${p}-demo" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  gcloud iam service-accounts delete "${p}-app@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  gcloud iam service-accounts delete "${p}-demo@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
}

destroy_lab_prefix "${LAB_PREFIX}"
destroy_lab_prefix "${LEGACY_PREFIX}"

if [[ "${LAB_ONLY}" == "true" ]]; then
  echo "Done. Lab stack removed; core automation kept."
  exit 0
fi

echo "Deleting foundation (core automation)..."
if [[ ! -f infra/foundation/terraform.tfvars ]]; then
  cat > infra/foundation/terraform.tfvars <<EOF
project_id  = "${PROJECT_ID}"
region      = "${REGION}"
name_prefix = "${PREFIX}"
enable_mock = true
EOF
fi

cd infra/foundation
terraform init -input=false -reconfigure >/dev/null || true
if [[ -f terraform.tfstate ]] && [[ "$(terraform state list 2>/dev/null | wc -l | tr -d ' ')" != "0" ]]; then
  terraform destroy -input=false -auto-approve || true
fi
cd "$ROOT"

echo "Cleaning leftover named resources (prefix=${PREFIX})..."
gcloud run jobs delete "${PREFIX}-sync" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud run services delete "${PREFIX}-mock" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud scheduler jobs delete "${PREFIX}-daily" --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud builds triggers delete "${PREFIX}-lab-https-lb" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud builds triggers delete "${PREFIX}-sample-https-lb" --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${PREFIX}-events" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${PREFIX}-lab-tf-apply" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${PREFIX}-sample-tf-apply" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud artifacts repositories delete "${PREFIX}" --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
for sa in sync mock sched; do
  gcloud iam service-accounts delete "${PREFIX}-${sa}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done
for secret in \
  "${PREFIX}-venafi-username" \
  "${PREFIX}-venafi-password" \
  "${PREFIX}-venafi-p12-password" \
  demo-cert-certificate \
  demo-cert-private-key \
  app-tls-certificate \
  app-tls-private-key \
  edge-tls-certificate \
  edge-tls-private-key
do
  gcloud secrets delete "${secret}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done
gsutil -m rm -r "gs://${TF_BUCKET}" >/dev/null 2>&1 || true

echo "Done."
