resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = var.name_prefix
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "build_tf_admin" {
  for_each = local.build_sas
  bucket   = var.tf_state_bucket
  role     = "roles/storage.objectAdmin"
  member   = each.value
}

resource "google_project_iam_member" "build_roles" {
  for_each = {
    for pair in setproduct(tolist(local.build_sas), [
      "roles/secretmanager.admin",
      "roles/certificatemanager.editor",
      "roles/compute.admin",
      "roles/iam.serviceAccountAdmin",
      "roles/artifactregistry.writer",
      "roles/run.admin",
      "roles/iam.serviceAccountUser",
    ]) : "${pair[0]}-${pair[1]}" => { member = pair[0], role = pair[1] }
  }
  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

resource "google_pubsub_topic" "tf_apply" {
  name       = "${var.name_prefix}-tf-apply"
  depends_on = [google_project_service.apis]
}

resource "google_cloudbuild_trigger" "app_https_lb" {
  name        = "${var.name_prefix}-https-lb"
  description = "Manual Run: apply HTTPS LB certificate from Secret Manager"
  location    = var.region
  project     = var.project_id

  service_account = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"

  pubsub_config {
    topic = google_pubsub_topic.tf_apply.id
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
        "gsutil cp gs://${var.tf_state_bucket}/${var.tf_source_object} /workspace/src.tgz && tar xzf /workspace/src.tgz -C /workspace",
      ]
    }

    step {
      name       = "hashicorp/terraform:1.9"
      dir        = "terraform"
      entrypoint = "sh"
      args = [
        "-c",
        <<-EOT
        set -eu
        cat > terraform.tfvars <<EOF
        project_id         = "${var.project_id}"
        region             = "${var.region}"
        name_prefix        = "${var.name_prefix}"
        secret_cert_name   = "${var.secret_cert_name}"
        secret_key_name    = "${var.secret_key_name}"
        status_app_image   = "${var.status_app_image}"
        tf_state_bucket    = "${var.tf_state_bucket}"
        EOF
        terraform init -input=false -reconfigure \
          -backend-config="bucket=${var.tf_state_bucket}" \
          -backend-config="prefix=edge-https-lb"
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
    google_project_iam_member.build_roles,
    google_storage_bucket_iam_member.build_tf_admin,
  ]
}
