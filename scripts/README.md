# Scripts

Requires `bash`, `gcloud`, `terraform`, and `python3` (Cloud Shell, macOS, Linux). The caller needs project Owner (or equivalent) plus `iam.serviceAccounts.actAs` on the default Compute Engine SA. See [Prerequisites](../README.md#prerequisites) in the main README for the full role list and Cloud Build SA grants.

| Script | Purpose |
| --- | --- |
| `./scripts/deploy.sh` | Apply Terraform, build images, update Cloud Run |
| `./scripts/run-sync.sh` | Run one Secret Manager scan/renew |
| `./scripts/set-venafi-secrets.sh` | Store real Venafi credentials |
| `./scripts/destroy.sh` | Tear down core automation only (examples have their own destroy scripts) |

## Prompt vs tfvars

Applies to `deploy.sh` and `destroy.sh` (core and examples).

Priority: env var > existing `terraform/terraform.tfvars` > prompt > default.

```hcl
# terraform/terraform.tfvars
scheduler_cron     = "0 2 * * 1-5"
scheduler_timezone = "America/New_York"
renew_days_before  = 45
alert_emails       = ["ops@example.com"]
```

```bash
SCHEDULER_CRON="0 */6 * * *" ./scripts/deploy.sh
```

Deploy does not ask for certificate count, CN, or DN. The job discovers secrets at runtime.
