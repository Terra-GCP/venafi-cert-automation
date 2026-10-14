# Lab verification kit (optional)

This folder documents the **lab-only** path. It is not required for client or production use.

## Why lab exists

Core automation (`./scripts/deploy.sh` mode 1) renews certificates that already exist in Venafi / Secret Manager and installs them onto infrastructure the client already operates.

Lab mode (deploy mode 2) is only for validation when:

- Corporate Venafi is not available yet
- You need a near-expiry certificate on purpose to prove renew works
- You want a temporary HTTPS status page and load balancer for before/after checks

Lab mode must stay off in client environments that already have certificates and edge infrastructure.

## How to run lab

```bash
./scripts/deploy.sh
# Deploy mode -> 2
```

Or non-interactive:

```bash
NONINTERACTIVE=true DEPLOY_MODE=lab PROJECT_ID=your-project ./scripts/deploy.sh
```

## What lab adds on top of core

- Mock Venafi TPP API
- Seeds 1–2 **near-expiry** certificates into Secret Manager (still valid, ~7 days left by default → secret **v1**)
- Deploys `infra/lab-https-lb` (verification HTTPS app + Certificate Manager + load balancer) **without** running renew during deploy
- After deploy, `./scripts/run-sync.sh` (force = **n**) renews to ~90 days → secret **v2**

## Tear down lab only

```bash
./scripts/destroy.sh
# Delete everything? -> n
```
