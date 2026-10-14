# Scripts

## Use these

| Script | When |
| --- | --- |
| `./scripts/deploy.sh` | Deploy. Mode **1 = core** (clients). Mode **2 = core + lab** (validation only). |
| `./scripts/run-sync.sh` | Run one renew/sync cycle |
| `./scripts/set-venafi-secrets.sh` | Store real Venafi credentials in Secret Manager |
| `./scripts/destroy.sh` | Tear down lab only, or everything |

## Core vs lab

| | Core (mode 1) | Lab (mode 2) |
| --- | --- | --- |
| Purpose | Renew existing Venafi certificates in a client project | Prove the flow without corporate Venafi |
| Expired seed certs | No | Yes (1–2 expired seeds for renew demo) |
| HTTPS status app / LB | No (use client's existing edge) | Yes (`infra/lab-https-lb`) |
| Mock Venafi | Optional | Yes |

See `scripts/lab/README.md` for lab details.

## Do not run directly

`scripts/internal/` is used by deploy / Terraform helpers only.
