from __future__ import annotations

import json
from typing import Any


def emit_cert_event(status: str, **fields: Any) -> None:
    """Emit a structured Cloud Logging event for Monitoring log-based alerts.

    Cloud Run captures JSON stdout as jsonPayload. Alert policies match:
      jsonPayload.message="VENAFI_CERT_EVENT" AND jsonPayload.status="renewed"
    """
    payload = {
        "severity": "NOTICE" if status in {"renewed", "skipped", "uploaded"} else "ERROR",
        "message": "VENAFI_CERT_EVENT",
        "status": status,
        **{k: v for k, v in fields.items() if v is not None},
    }
    print(json.dumps(payload, default=str), flush=True)
