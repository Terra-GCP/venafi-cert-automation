# Scripts

| Script | Purpose |
| --- | --- |
| `./scripts/deploy.sh` | Deploy sync job, scheduler, alerts |
| `./scripts/run-sync.sh` | Run one Secret Manager scan/renew |
| `./scripts/set-venafi-secrets.sh` | Store real Venafi credentials |
| `./scripts/destroy.sh` | Tear down core automation (asks whether to also destroy examples) |

## Prompt vs tfvars

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
