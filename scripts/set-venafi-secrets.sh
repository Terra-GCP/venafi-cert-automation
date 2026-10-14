#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=internal/lib.sh
source "${ROOT}/scripts/internal/lib.sh"

PROJECT_ID="${PROJECT_ID:-}"
PREFIX="${PREFIX:-venafi-cert}"

if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(ask "GCP project ID" "")"
fi
if [[ -z "${PROJECT_ID}" ]]; then
  echo "GCP project ID is required" >&2
  exit 1
fi

echo "Venafi credentials are written only to Google Secret Manager (never to tfvars or git)."
VENAFI_USERNAME="$(ask "Username" "${VENAFI_USERNAME:-}")"
VENAFI_PASSWORD="$(ask_secret "Password")"
VENAFI_P12_PASSWORD="$(ask_secret "PKCS#12 password (used when exporting the certificate)")"

printf '%s' "${VENAFI_USERNAME}" | gcloud secrets versions add "${PREFIX}-venafi-username" \
  --project="${PROJECT_ID}" --data-file=-
printf '%s' "${VENAFI_PASSWORD}" | gcloud secrets versions add "${PREFIX}-venafi-password" \
  --project="${PROJECT_ID}" --data-file=-
printf '%s' "${VENAFI_P12_PASSWORD}" | gcloud secrets versions add "${PREFIX}-venafi-p12-password" \
  --project="${PROJECT_ID}" --data-file=-

unset VENAFI_USERNAME VENAFI_PASSWORD VENAFI_P12_PASSWORD
echo "Saved secrets: ${PREFIX}-venafi-username, ${PREFIX}-venafi-password, ${PREFIX}-venafi-p12-password"