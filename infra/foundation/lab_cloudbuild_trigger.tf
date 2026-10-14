# Optional lab verification stack only. Not created for core / client deploys.
resource "google_pubsub_topic" "lab_tf_apply" {
  count      = var.enable_lab_stack ? 1 : 0
  name       = "${var.name_prefix}-lab-tf-apply"
  depends_on = [google_project_service.apis]
}

resource "google_cloudbuild_trigger" "lab_https_lb" {
  count       = var.enable_lab_stack ? 1 : 0
  name        = "${var.name_prefix}-lab-https-lb"
  description = "Plan and apply lab HTTPS load balancer certificate from Secret Manager"
  location    = var.region
  project     = var.project_id

  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  pubsub_config {
    topic = google_pubsub_topic.lab_tf_apply[0].id
  }

  substitutions = {
    _MODE = "apply"
  }

  build {
    timeout = "1800s"

    step {
      name       = "gcr.io/cloud-builders/gsutil"
      entrypoint = "bash"
      args = [
        "-c",
        "gsutil cp gs://${google_storage_bucket.tf.name}/${var.tf_source_object} /workspace/src.tgz && tar xzf /workspace/src.tgz -C /workspace",
      ]
    }

    step {
      name       = "hashicorp/terraform:1.9"
      dir        = "infra/lab-https-lb"
      entrypoint = "sh"
      args = [
        "-c",
        <<-EOT
        set -eu
        cat > terraform.tfvars <<EOF
        project_id         = "${var.project_id}"
        region             = "${var.region}"
        name_prefix        = "${local.lab_name_prefix}"
        secret_cert_name   = "${google_secret_manager_secret.certificate.secret_id}"
        secret_key_name    = "${google_secret_manager_secret.private_key.secret_id}"
        status_app_image   = "${local.status_app_image}"
        EOF
        terraform init -input=false -reconfigure \
          -backend-config="bucket=${google_storage_bucket.tf.name}" \
          -backend-config="prefix=lab-https-lb"
        echo "======== TERRAFORM PLAN ========"
        terraform plan -input=false -no-color -out=tfplan
        echo "======== PLAN DETAILS ========"
        terraform show -no-color tfplan
        if [ "$${_MODE}" = "plan" ]; then
          echo "MODE=plan; apply skipped"
          exit 0
        fi
        echo "======== TERRAFORM APPLY ========"
        terraform apply -input=false -auto-approve tfplan
        EOT
      ]
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.build_sa_user,
    google_project_iam_member.build_compute_admin,
  ]
}
