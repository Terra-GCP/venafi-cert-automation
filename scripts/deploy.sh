#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
PREFIX="${PREFIX:-venafi-cert}"
CERT_NAME="${CERT_NAME:-app-tls}"
CERT_CN="${CERT_CN:-app.example.local}"
USE_MOCK="${USE_MOCK:-false}"
VENAFI_PLATFORM="${VENAFI_PLATFORM:-tpp}"
VENAFI_BASE_URL="${VENAFI_BASE_URL:-}"
VENAFI_CERTIFICATE_DN="${VENAFI_CERTIFICATE_DN:-\\\\VED\\\\Policy\\\\Apps\\\\app.example.local}"
CERT_INSTALL_METHOD="${CERT_INSTALL_METHOD:-cm_api}"
CERT_MAP_NAME="${CERT_MAP_NAME:-}"
CERT_MAP_ENTRY_NAME="${CERT_MAP_ENTRY_NAME:-}"
EXTERNAL_TF_TRIGGER="${EXTERNAL_TF_TRIGGER:-}"
DEPLOY_MODE="${DEPLOY_MODE:-core}"
NONINTERACTIVE="${NONINTERACTIVE:-false}"
DELETE_OLD_FIRST="${DELETE_OLD_FIRST:-false}"

echo ""
echo "Deploy Venafi certificate automation"
echo ""

if [[ "${NONINTERACTIVE}" == "true" ]]; then
  if [[ -z "${PROJECT_ID}" ]]; then
    echo "PROJECT_ID is required when NONINTERACTIVE=true" >&2
    exit 1
  fi
  echo "Non-interactive: mode=${DEPLOY_MODE} project=${PROJECT_ID} region=${REGION} prefix=${PREFIX} mock=${USE_MOCK} method=${CERT_INSTALL_METHOD}"
else
  echo "What do you want to deploy?"
  echo "  1 = Core automation only (client / production; renews existing Venafi certificates)"
  echo "  2 = Core + lab verification kit (mock-friendly; seeds near-expiry certs + HTTPS status app for testing)"
  mode_choice="$(ask "Deploy mode" "1")"
  case "${mode_choice}" in
    2) DEPLOY_MODE="lab" ;;
    *) DEPLOY_MODE="core" ;;
  esac

  PROJECT_ID="$(ask "GCP project ID" "${PROJECT_ID}")"
  REGION="$(ask "GCP region" "${REGION}")"
  PREFIX="$(ask "Resource name prefix" "${PREFIX}")"
  CERT_NAME="$(ask "Certificate logical name (Secret Manager prefix)" "${CERT_NAME}")"

  if [[ "${DEPLOY_MODE}" == "lab" ]]; then
    USE_MOCK=true
    CERT_CN="$(ask "Certificate common name (lab)" "${CERT_CN}")"
    VENAFI_CERTIFICATE_DN="$(ask "Certificate DN (mock)" "\\\\VED\\\\Policy\\\\Apps\\\\${CERT_CN}")"
  else
    echo ""
    echo "  y = mock Venafi (only if you still need a dry-run without corporate Venafi)"
    echo "  n = real Venafi Trust Protection Platform (typical client deploy)"
    if ask_yn "Use mock Venafi?" "n"; then
      USE_MOCK=true
      CERT_CN="$(ask "Certificate common name" "${CERT_CN}")"
      VENAFI_CERTIFICATE_DN="$(ask "Certificate DN (mock)" "\\\\VED\\\\Policy\\\\Apps\\\\${CERT_CN}")"
    else
      USE_MOCK=false
      VENAFI_PLATFORM="$(ask "Venafi platform (tpp)" "${VENAFI_PLATFORM}")"
      VENAFI_BASE_URL="$(ask "Venafi base URL" "${VENAFI_BASE_URL:-https://venafi.example.com}")"
      VENAFI_CERTIFICATE_DN="$(ask "Certificate DN in Venafi" "${VENAFI_CERTIFICATE_DN}")"
    fi
  fi

  echo ""
  echo "After renew, install with exactly one method:"
  echo "  1 = Certificate Manager API (client already has a cert map)"
  echo "  2 = Terraform via Cloud Build trigger"
  echo "  3 = none (Secret Manager only)"
  install_choice="$(ask "Install method" "1")"
  case "${install_choice}" in
    2) CERT_INSTALL_METHOD="tf_cloudbuild" ;;
    3) CERT_INSTALL_METHOD="none" ;;
    *) CERT_INSTALL_METHOD="cm_api" ;;
  esac

  if [[ "${CERT_INSTALL_METHOD}" == "cm_api" && "${DEPLOY_MODE}" == "core" ]]; then
    CERT_MAP_NAME="$(ask "Existing Certificate Manager map name" "${CERT_MAP_NAME}")"
    CERT_MAP_ENTRY_NAME="$(ask "Existing Certificate Manager map entry name" "${CERT_MAP_ENTRY_NAME}")"
  fi

  if [[ "${CERT_INSTALL_METHOD}" == "tf_cloudbuild" && "${DEPLOY_MODE}" == "core" ]]; then
    EXTERNAL_TF_TRIGGER="$(ask "Existing Cloud Build trigger name (client Terraform)" "${EXTERNAL_TF_TRIGGER}")"
  fi

  if ask_yn "Delete existing deployment first?" "n"; then
    DELETE_OLD_FIRST=true
  fi
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

ENABLE_LAB=false
SEED_EXPIRED=false
SECONDARY_CERT_NAME=""
SECONDARY_CERT_CN=""
if [[ "${DEPLOY_MODE}" == "lab" ]]; then
  ENABLE_LAB=true
  SEED_EXPIRED=true
  SECONDARY_CERT_NAME="${SECONDARY_CERT_NAME:-edge-tls}"
  SECONDARY_CERT_CN="${SECONDARY_CERT_CN:-edge.example.local}"
  USE_MOCK=true
fi

if [[ "${DELETE_OLD_FIRST}" == "true" ]]; then
  NONINTERACTIVE=true PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" PREFIX="${PREFIX}" LAB_ONLY=false \
    "${ROOT}/scripts/destroy.sh"
fi

gcloud config set project "${PROJECT_ID}" >/dev/null
REPO_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${PREFIX}"

echo ""
echo "Working (mode=${DEPLOY_MODE})..."

gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com cloudscheduler.googleapis.com pubsub.googleapis.com \
  compute.googleapis.com certificatemanager.googleapis.com iam.googleapis.com storage.googleapis.com \
  --project="${PROJECT_ID}" >/dev/null

write_tfvars() {
  local map_name="${1:-}" map_entry="${2:-}" status_image="${3:-}"
  local seed_mock="false"
  [[ "${USE_MOCK}" == "true" ]] && seed_mock="true"
  cat > infra/foundation/terraform.tfvars <<EOF
project_id                    = "${PROJECT_ID}"
region                        = "${REGION}"
name_prefix                   = "${PREFIX}"
cert_name                     = "${CERT_NAME}"
cert_common_name              = "${CERT_CN}"
secondary_cert_name           = "${SECONDARY_CERT_NAME}"
secondary_cert_common_name    = "${SECONDARY_CERT_CN}"
enable_mock                   = ${USE_MOCK}
seed_mock_secret_versions     = ${seed_mock}
enable_lab_stack              = ${ENABLE_LAB}
seed_expired_certificates     = ${SEED_EXPIRED}
seed_days_until_expiry        = ${SEED_DAYS_UNTIL_EXPIRY:-7}
cert_install_method           = "${CERT_INSTALL_METHOD}"
lab_name_prefix               = "${PREFIX}-lab"
external_tf_cloudbuild_trigger = "${EXTERNAL_TF_TRIGGER}"
venafi_platform               = "${VENAFI_PLATFORM}"
venafi_base_url               = "${VENAFI_BASE_URL}"
venafi_certificate_dn         = "${VENAFI_CERTIFICATE_DN}"
EOF
  [[ -n "${status_image}" ]] && echo "status_app_image = \"${status_image}\"" >> infra/foundation/terraform.tfvars
  if [[ -n "${map_name}" && -n "${map_entry}" ]]; then
    echo "cert_map_name = \"${map_name}\"" >> infra/foundation/terraform.tfvars
    echo "cert_map_entry_name = \"${map_entry}\"" >> infra/foundation/terraform.tfvars
  elif [[ -n "${CERT_MAP_NAME}" && -n "${CERT_MAP_ENTRY_NAME}" ]]; then
    echo "cert_map_name = \"${CERT_MAP_NAME}\"" >> infra/foundation/terraform.tfvars
    echo "cert_map_entry_name = \"${CERT_MAP_ENTRY_NAME}\"" >> infra/foundation/terraform.tfvars
  fi
}

write_tfvars

cd infra/foundation
terraform init -input=false >/dev/null
terraform apply -input=false -auto-approve \
  -target=google_project_service.apis \
  -target=google_artifact_registry_repository.repo >/dev/null
REPO_PATH="$(terraform output -raw repo_path)"
cd "$ROOT"

need_images=false
gcloud artifacts docker images describe "${REPO_PATH}/cert-sync:latest" --project="${PROJECT_ID}" >/dev/null 2>&1 || need_images=true
if [[ "${USE_MOCK}" == "true" ]]; then
  gcloud artifacts docker images describe "${REPO_PATH}/mock-venafi:latest" --project="${PROJECT_ID}" >/dev/null 2>&1 || need_images=true
fi
if [[ "${ENABLE_LAB}" == "true" ]]; then
  gcloud artifacts docker images describe "${REPO_PATH}/cert-status-app:latest" --project="${PROJECT_ID}" >/dev/null 2>&1 || need_images=true
fi

if [[ "${need_images}" == "true" ]]; then
  echo "Building images..."
  TAG="$(date +%Y%m%d%H%M%S)"
  gcloud builds submit --project="${PROJECT_ID}" --config=cloudbuild/build-images.yaml \
    --substitutions=_REGION="${REGION}",_REPO="${PREFIX}",_TAG="${TAG}" .
else
  echo "Images already exist, skipping build"
fi

echo "Creating foundation (core automation)..."
cd infra/foundation
terraform apply -input=false -auto-approve
JOB_NAME="$(terraform output -raw cert_sync_job)"
SECRET_CERT="$(terraform output -raw secret_cert_name)"
SECRET_KEY="$(terraform output -raw secret_key_name)"
TF_BUCKET="$(terraform output -raw tf_bucket)"
TRIGGER="$(terraform output -raw resolved_tf_trigger 2>/dev/null || true)"
cd "$ROOT"

if [[ "${USE_MOCK}" != "true" ]]; then
  if ! gcloud secrets versions access latest --secret="${PREFIX}-venafi-password" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Enter Venafi credentials (stored only in Secret Manager):"
    PROJECT_ID="${PROJECT_ID}" PREFIX="${PREFIX}" "${ROOT}/scripts/set-venafi-secrets.sh"
  fi
fi

if [[ "${ENABLE_LAB}" == "true" ]]; then
  # Do not renew during deploy: seed leaves secret v1 near-expiry so the lab URL
  # shows a due cert; the next sync / scheduler run produces v2 (~90 days).
  echo "Lab mode: uploading lab Terraform package (keeping near-expiry seed; no renew yet)..."
  PROJECT_ID="${PROJECT_ID}" PREFIX="${PREFIX}" TF_BUCKET="${TF_BUCKET}" \
    "${ROOT}/scripts/internal/upload-tf-source.sh"
  echo "Creating lab HTTPS verification stack (local Terraform)..."
  cat > infra/lab-https-lb/terraform.tfvars <<EOF
project_id         = "${PROJECT_ID}"
region             = "${REGION}"
name_prefix        = "${PREFIX}-lab"
secret_cert_name   = "${SECRET_CERT}"
secret_key_name    = "${SECRET_KEY}"
status_app_image   = "${REPO_PATH}/cert-status-app:latest"
EOF
  cd infra/lab-https-lb
  terraform init -input=false -reconfigure \
    -backend-config="bucket=${TF_BUCKET}" \
    -backend-config="prefix=lab-https-lb" >/dev/null
  terraform apply -input=false -auto-approve
  LB_IP="$(terraform output -raw lb_ip)"
  MAP_NAME="$(terraform output -raw certificate_map)"
  MAP_ENTRY="$(terraform output -raw certificate_map_entry)"
  cd "$ROOT"
  write_tfvars "${MAP_NAME}" "${MAP_ENTRY}" "${REPO_PATH}/cert-status-app:latest"
  cd infra/foundation
  terraform apply -input=false -auto-approve >/dev/null
  cd "$ROOT"
else
  LB_IP=""
  echo "Core mode: no lab seeds and no lab load balancer were created."
  echo "Point CERT_MAP_* or EXTERNAL_TF_TRIGGER at your existing environment, then run ./scripts/run-sync.sh"
fi

echo ""
echo "Ready."
echo "  Mode:           ${DEPLOY_MODE}"
echo "  Project:        ${PROJECT_ID}"
echo "  Region:         ${REGION}"
echo "  Prefix:         ${PREFIX}"
echo "  Install method: ${CERT_INSTALL_METHOD}"
echo "  Sync job:       ${JOB_NAME}"
[[ -n "${TRIGGER}" && "${TRIGGER}" != "null" ]] && echo "  TF trigger:     ${TRIGGER}"
if [[ -n "${LB_IP}" ]]; then
  echo "  Lab URL:        https://${LB_IP}/"
  echo "  Cert JSON:      https://${LB_IP}/api/cert"
  echo ""
  echo "Lab baseline: secret v1 should show ~7 days left (near expiry)."
  echo "Then run sync without force to renew to ~90 days (secret v2):"
  echo "  ./scripts/run-sync.sh"
else
  echo "Run sync: ./scripts/run-sync.sh"
fi
echo ""
