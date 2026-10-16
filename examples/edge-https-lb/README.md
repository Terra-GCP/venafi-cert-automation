# Example: edge HTTPS load balancer

Same pattern as [`../app-https-lb`](../app-https-lb/), with default secrets `edge-tls-certificate` / `edge-tls-private-key`.

```bash
./scripts/deploy.sh
```

Near-expiry seed is automatic (`SEED_NEAR_EXPIRY=false` to skip). Status page shows the cert from the last Terraform apply; sync alone does not change the page or LB.
