# Example: app HTTPS load balancer

Creates and seeds `app-tls-certificate` / `app-tls-private-key`, then deploys a status app and HTTPS LB.

The status page shows the cert from the last Terraform apply (same PEM as Certificate Manager). Sync updates Secret Manager only. Re-apply this stack or run the Cloud Build trigger to refresh the LB and page.

## Deploy

```bash
./scripts/deploy.sh
```

Seeding a near-expiry cert is automatic (needed for the renew demo). Skip only with `SEED_NEAR_EXPIRY=false`.

## Renew demo

1. Open `https://LB_IP/` and note CN, expiry, serial, SM version
2. From repo root: `./scripts/run-sync.sh` (page stays unchanged)
3. Cloud Build Triggers: `{prefix}-https-lb` -> Run
4. Refresh the page

## Destroy

```bash
./scripts/destroy.sh
```
