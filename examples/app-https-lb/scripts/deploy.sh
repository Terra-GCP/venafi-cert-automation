#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${EXAMPLE_ROOT}/../.." && pwd)"
# shellcheck source=../../../scripts/internal/lib.sh
source "${REPO_ROOT}/scripts/internal/lib.sh"
cd "${EXAMPLE_ROOT}"

TFVARS="${EXAMPLE_ROOT}/terraform/terraform.tfvars"
NONINTERACTIVE="${NONINTERACTIVE:-false}"
FORCE_IMAGE_BUILD="${FORCE_IMAGE_BUILD:-false}"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-}"
APP_PREFIX="${APP_PREFIX:-}"
CERT_NAME="${CERT_NAME:-}"
CERT_CN="${CERT_CN:-}"
SEED_DAYS="${SEED_DAYS:-}"
SEED_NEAR_EXPIRY="${SEED_NEAR_EXPIRY:-}"

echo ""
echo "Deploy example app HTTPS LB stack"
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
resolve_str CERT_NAME "Secret Manager cert prefix (logical name)" "app-tls"
resolve_str CERT_CN "Common name for near-expiry seed" "app.example.local"
resolve_str SEED_DAYS "Days until seeded cert expires" "7"
SEED_NEAR_EXPIRY="${SEED_NEAR_EXPIRY:-true}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

SECRET_CERT="${CERT_NAME}-certificate"
SECRET_KEY="${CERT_NAME}-private-key"
TF_BUCKET="${PROJECT_ID}-${APP_PREFIX}-tf"
REPO_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${APP_PREFIX}"
STATUS_IMAGE="${REPO_PATH}/cert-status-app:latest"
APP_SERVICE="${APP_PREFIX}-app"

gcloud config set project "${PROJECT_ID}" >/dev/null

gcloud services enable \
  secretmanager.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com certificatemanager.googleapis.com \
  compute.googleapis.com \
  --project="${PROJECT_ID}" >/dev/null

echo "Ensuring Terraform state bucket..."
if ! gsutil ls -b "gs://${TF_BUCKET}" >/dev/null 2>&1; then
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" "gs://${TF_BUCKET}"
fi

if [[ "${SEED_NEAR_EXPIRY}" == "true" ]]; then
  echo "Creating/seeding near-expiry certificate in Secret Manager (~${SEED_DAYS}d left)..."
  VENV="${TMPDIR:-/tmp}/venafi-app-seed-venv"
  python3 -m venv "${VENV}"
  "${VENV}/bin/pip" install --quiet -r scripts/internal/requirements-seed.txt
  "${VENV}/bin/python" scripts/internal/seed_near_expiry.py \
    --project-id "${PROJECT_ID}" \
    --specs "${CERT_NAME}:${CERT_CN}" \
    --days-until-expiry "${SEED_DAYS}"
else
  if ! gcloud secrets describe "${SECRET_CERT}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Secret ${SECRET_CERT} not found and seeding is disabled." >&2
    echo "Re-run with SEED_NEAR_EXPIRY=true or answer y to the seed prompt." >&2
    exit 1
  fi
fi

cat > "${TFVARS}" <<EOF
project_id         = "${PROJECT_ID}"
region             = "${REGION}"
name_prefix        = "${APP_PREFIX}"
secret_cert_name   = "${SECRET_CERT}"
secret_key_name    = "${SECRET_KEY}"
tf_state_bucket    = "${TF_BUCKET}"
EOF

echo "Uploading Terraform package for Cloud Build trigger..."
PROJECT_ID="${PROJECT_ID}" TF_BUCKET="${TF_BUCKET}" \
  scripts/internal/upload-tf-source.sh

echo "Terraform apply..."
cd terraform
terraform init -input=false -reconfigure \
  -backend-config="bucket=${TF_BUCKET}" \
  -backend-config="prefix=app-https-lb" >/dev/null
terraform apply -input=false -auto-approve
LB_IP="$(terraform output -raw lb_ip)"
TRIGGER="$(terraform output -raw trigger_name)"
cd "${EXAMPLE_ROOT}"

need_image=false
gcloud artifacts docker images describe "${STATUS_IMAGE}" --project="${PROJECT_ID}" >/dev/null 2>&1 || need_image=true
if [[ "${FORCE_IMAGE_BUILD}" == "true" || "${need_image}" == "true" ]]; then
  echo "Building status app image..."
  TAG="$(date +%Y%m%d%H%M%S)"
  gcloud builds submit --project="${PROJECT_ID}" --config=cloudbuild/build-status-app.yaml \
    --substitutions=_REGION="${REGION}",_REPO="${APP_PREFIX}",_TAG="${TAG}" .
fi

echo "Updating Cloud Run images..."
gcloud run services update "${APP_SERVICE}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --image="${STATUS_IMAGE}"

echo ""
echo "Example stack ready."
echo "  App URL:    https://${LB_IP}/"
echo "  Cert JSON:  https://${LB_IP}/api/cert"
echo "  Secrets:    ${SECRET_CERT} / ${SECRET_KEY}"
echo "  CB trigger: ${TRIGGER}"
echo ""
echo "Renew demo: ./scripts/run-sync.sh then Cloud Build Triggers > ${TRIGGER} > Run"
echo ""
