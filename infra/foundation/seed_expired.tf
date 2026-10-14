resource "google_secret_manager_secret" "secondary_certificate" {
  count     = var.enable_lab_stack && var.secondary_cert_name != "" ? 1 : 0
  secret_id = "${var.secondary_cert_name}-certificate"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "secondary_private_key" {
  count     = var.enable_lab_stack && var.secondary_cert_name != "" ? 1 : 0
  secret_id = "${var.secondary_cert_name}-private-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "null_resource" "seed_expired_certificates" {
  # Lab / validation only. Never enable for client environments with existing certificates.
  # Seeds a still-valid near-expiry cert (secret v1) so deploy can put it on the lab LB;
  # the next sync / scheduler run renews it without FORCE_RENEW.
  count = var.enable_lab_stack && var.seed_expired_certificates ? 1 : 0

  triggers = {
    project_id         = var.project_id
    primary            = var.cert_name
    secondary          = var.secondary_cert_name
    cn                 = var.cert_common_name
    secondary_cn       = var.secondary_cert_common_name
    days_until_expiry  = tostring(var.seed_days_until_expiry)
  }

  depends_on = [
    google_secret_manager_secret.certificate,
    google_secret_manager_secret.private_key,
    google_secret_manager_secret.secondary_certificate,
    google_secret_manager_secret.secondary_private_key,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      VENV="$${TMPDIR:-/tmp}/venafi-cert-seed-venv"
      python3 -m venv "$${VENV}"
      "$${VENV}/bin/pip" install --quiet -r "${path.module}/../../scripts/internal/requirements-seed.txt"
      SPECS="${var.cert_name}:${var.cert_common_name}"
      if [ -n "${var.secondary_cert_name}" ]; then
        SPECS="$${SPECS},${var.secondary_cert_name}:${var.secondary_cert_common_name}"
      fi
      "$${VENV}/bin/python" "${path.module}/../../scripts/internal/seed_expired_certs.py" \
        --project-id "${var.project_id}" \
        --specs "$${SPECS}" \
        --days-until-expiry "${var.seed_days_until_expiry}"
    EOT
  }
}