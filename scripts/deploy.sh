#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"
cd "$ROOT"

TFVARS="${ROOT}/terraform/terraform.tfvars"
NONINTERACTIVE="${NONINTERACTIVE:-false}"
DELETE_OLD_FIRST="${DELETE_OLD_FIRST:-false}"
FORCE_IMAGE_BUILD="${FORCE_IMAGE_BUILD:-false}"

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-}"
PREFIX="${PREFIX:-}"
USE_MOCK="${USE_MOCK:-}"
VENAFI_PLATFORM="${VENAFI_PLATFORM:-}"
VENAFI_BASE_URL="${VENAFI_BASE_URL:-}"
ALERT_EMAILS="${ALERT_EMAILS:-}"
NOTIFICATION_CHANNEL_IDS="${NOTIFICATION_CHANNEL_IDS:-}"
ENABLE_RENEW_ALERTS="${ENABLE_RENEW_ALERTS:-}"
ENABLE_FAILURE_ALERTS="${ENABLE_FAILURE_ALERTS:-}"
ENABLE_PUBSUB_EVENTS="${ENABLE_PUBSUB_EVENTS:-}"
RENEW_DAYS_BEFORE="${RENEW_DAYS_BEFORE:-}"
SCHEDULER_CRON="${SCHEDULER_CRON:-}"
SCHEDULER_TIMEZONE="${SCHEDULER_TIMEZONE:-}"

echo ""
echo "Deploy Venafi certificate automation"
echo "  Scans Secret Manager for *-certificate / *-private-key pairs near expiry"
echo "  Env and terraform.tfvars values are reused; only missing values are prompted"
echo ""

resolve_str PROJECT_ID "GCP project ID" "" "project_id" "${TFVARS}"
resolve_str REGION "GCP region" "us-central1" "region" "${TFVARS}"
resolve_str PREFIX "Resource name prefix" "venafi-cert" "name_prefix" "${TFVARS}"

if [[ -z "${USE_MOCK}" ]] && tfvar_has "${TFVARS}" "enable_mock"; then
  USE_MOCK="$(tfvar_get "${TFVARS}" "enable_mock")"
  echo "  USE_MOCK: using terraform.tfvars (enable_mock=${USE_MOCK})" >&2
fi
resolve_bool USE_MOCK "Use mock Venafi?" "false"

if [[ "${USE_MOCK}" == "true" ]]; then
  VENAFI_PLATFORM="${VENAFI_PLATFORM:-tpp}"
  VENAFI_BASE_URL="${VENAFI_BASE_URL:-}"
else
  resolve_str VENAFI_PLATFORM "Venafi platform (tpp)" "tpp" "venafi_platform" "${TFVARS}"
  resolve_str VENAFI_BASE_URL "Venafi base URL" "https://venafi.example.com" "venafi_base_url" "${TFVARS}"
fi

resolve_str RENEW_DAYS_BEFORE "Renew when days left <=" "30" "renew_days_before" "${TFVARS}"
resolve_str SCHEDULER_CRON "Cloud Scheduler cron (UTC by default)" "0 6 * * *" "scheduler_cron" "${TFVARS}"
resolve_str SCHEDULER_TIMEZONE "Scheduler timezone" "UTC" "scheduler_timezone" "${TFVARS}"

resolve_bool ENABLE_RENEW_ALERTS "Enable renew email alerts?" "true" "enable_renew_alerts" "${TFVARS}"
resolve_bool ENABLE_FAILURE_ALERTS "Enable failure email alerts?" "true" "enable_failure_alerts" "${TFVARS}"
resolve_bool ENABLE_PUBSUB_EVENTS "Enable optional Pub/Sub events topic?" "false" "enable_pubsub_events" "${TFVARS}"

if [[ -z "${ALERT_EMAILS}" ]] && tfvar_has "${TFVARS}" "alert_emails"; then
  ALERT_EMAILS="$(tfvar_get "${TFVARS}" "alert_emails")"
  echo "  ALERT_EMAILS=${ALERT_EMAILS} (from terraform.tfvars)" >&2
fi
if [[ -z "${NOTIFICATION_CHANNEL_IDS}" ]] && tfvar_has "${TFVARS}" "notification_channel_ids"; then
  NOTIFICATION_CHANNEL_IDS="$(tfvar_get "${TFVARS}" "notification_channel_ids")"
  echo "  NOTIFICATION_CHANNEL_IDS=${NOTIFICATION_CHANNEL_IDS} (from terraform.tfvars)" >&2
fi

if [[ "${NONINTERACTIVE}" != "true" ]]; then
  if [[ -z "${ALERT_EMAILS}" ]]; then
    ALERT_EMAILS="$(ask "Alert email(s), comma-separated (blank to skip)" "")"
  fi
  if [[ -z "${NOTIFICATION_CHANNEL_IDS}" ]]; then
    NOTIFICATION_CHANNEL_IDS="$(ask "Existing notification channel IDs, comma-separated (blank ok)" "")"
  fi
  if ask_yn "Delete existing automation first?" "n"; then
    DELETE_OLD_FIRST=true
  fi
fi

if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required (set project_id in terraform.tfvars, PROJECT_ID=…, or answer the prompt)" >&2
  exit 1
fi

seed_mock="false"
[[ "${USE_MOCK}" == "true" ]] && seed_mock="true"

ALERT_EMAILS_HCL="$(hcl_list "${ALERT_EMAILS}")"
CHANNEL_IDS_HCL="$(hcl_list "${NOTIFICATION_CHANNEL_IDS}")"

if [[ "${DELETE_OLD_FIRST}" == "true" ]]; then
  NONINTERACTIVE=true PROJECT_ID="${PROJECT_ID}" REGION="${REGION}" PREFIX="${PREFIX}" \
    "${ROOT}/scripts/destroy.sh"
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

echo ""
echo "Working..."

gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com cloudscheduler.googleapis.com pubsub.googleapis.com \
  iam.googleapis.com logging.googleapis.com monitoring.googleapis.com \
  --project="${PROJECT_ID}" >/dev/null

rm -f terraform/certificates.auto.tfvars.json

cat > "${TFVARS}" <<EOF
project_id                = "${PROJECT_ID}"
region                    = "${REGION}"
name_prefix               = "${PREFIX}"
enable_mock               = ${USE_MOCK}
seed_mock_secret_versions = ${seed_mock}
venafi_platform           = "${VENAFI_PLATFORM}"
venafi_base_url           = "${VENAFI_BASE_URL}"
renew_days_before         = ${RENEW_DAYS_BEFORE}
scheduler_cron            = "${SCHEDULER_CRON}"
scheduler_timezone        = "${SCHEDULER_TIMEZONE}"
enable_renew_alerts       = ${ENABLE_RENEW_ALERTS}
enable_failure_alerts     = ${ENABLE_FAILURE_ALERTS}
enable_pubsub_events      = ${ENABLE_PUBSUB_EVENTS}
alert_emails              = ${ALERT_EMAILS_HCL}
notification_channel_ids  = ${CHANNEL_IDS_HCL}
EOF

cd terraform
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

if [[ "${FORCE_IMAGE_BUILD}" == "true" || "${need_images}" == "true" ]]; then
  echo "Building images..."
  TAG="$(date +%Y%m%d%H%M%S)"
  gcloud builds submit --project="${PROJECT_ID}" --config=cloudbuild/build-images.yaml \
    --substitutions=_REGION="${REGION}",_REPO="${PREFIX}",_TAG="${TAG}" .
else
  echo "Images already exist, skipping build (set FORCE_IMAGE_BUILD=true to rebuild)"
fi

echo "Creating automation..."
cd terraform
terraform apply -input=false -auto-approve
JOB_NAME="$(terraform output -raw cert_sync_job)"
NOTIFY_TOPIC="$(terraform output -raw notify_topic 2>/dev/null || true)"
echo "Discovery settings:"
terraform output -json discovery | python3 -m json.tool
cd "$ROOT"

if [[ "${USE_MOCK}" != "true" ]]; then
  if ! gcloud secrets versions access latest --secret="${PREFIX}-venafi-password" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Enter Venafi credentials (stored only in Secret Manager):"
    PROJECT_ID="${PROJECT_ID}" PREFIX="${PREFIX}" "${ROOT}/scripts/set-venafi-secrets.sh"
  fi
fi

echo ""
echo "Ready."
echo "  Project:     ${PROJECT_ID}"
echo "  Region:      ${REGION}"
echo "  Prefix:      ${PREFIX}"
echo "  Sync job:    ${JOB_NAME}"
echo "  Schedule:    ${SCHEDULER_CRON} (${SCHEDULER_TIMEZONE})"
echo "  Behavior:    scans project Secret Manager for *-certificate pairs near expiry"
[[ -n "${NOTIFY_TOPIC}" && "${NOTIFY_TOPIC}" != "null" ]] && echo "  Events topic:${NOTIFY_TOPIC}"
echo ""
if [[ -n "${ALERT_EMAILS}" ]]; then
  echo "Verify email notification channel(s) in Monitoring (Google sends a confirm link)."
fi
echo "Run sync: ./scripts/run-sync.sh"
echo "Demo near-expiry cert + LB: examples/app-https-lb/"
echo ""
