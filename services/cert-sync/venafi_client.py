from __future__ import annotations

from pathlib import Path
from urllib.parse import urlparse

import google.auth.transport.requests
import google.oauth2.id_token
import requests

from config import Settings


class VenafiClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.session = requests.Session()
        self.session.verify = settings.tls_verify
        self._attach_cloud_run_identity()

    def _attach_cloud_run_identity(self) -> None:
        host = urlparse(self.settings.base_url).hostname or ""
        if not host.endswith(".run.app"):
            return
        request = google.auth.transport.requests.Request()
        token = google.oauth2.id_token.fetch_id_token(request, self.settings.base_url)
        self.session.headers["X-Serverless-Authorization"] = f"Bearer {token}"

    def authenticate(self) -> str:
        if self.settings.platform == "cloud":
            if not self.settings.api_key:
                raise SystemExit("VENAFI_API_KEY is required when VENAFI_PLATFORM=cloud")
            self.session.headers["tppl-api-key"] = self.settings.api_key
            return "cloud-api-key"

        if self.settings.access_token:
            token = self.settings.access_token
        else:
            if not self.settings.username or not self.settings.password:
                raise SystemExit(
                    "Set VENAFI_ACCESS_TOKEN or VENAFI_USERNAME + VENAFI_PASSWORD"
                )
            token = self._authorize_tpp()

        self.session.headers["Authorization"] = f"Bearer {token}"
        return "tpp-token"

    def _authorize_tpp(self) -> str:
        attempts = [
            (
                f"{self.settings.base_url}/vedauth/authorize/oauth",
                "json",
                {
                    "client_id": "vcert.py",
                    "username": self.settings.username,
                    "password": self.settings.password,
                    "scope": "certificate:manage,discover",
                },
            ),
            (
                f"{self.settings.base_url}/vedauth/authorize/oauth",
                "form",
                {
                    "client_id": "vcert-cli",
                    "username": self.settings.username,
                    "password": self.settings.password,
                    "scope": "certificate:manage",
                },
            ),
            (
                f"{self.settings.base_url}/vedauth/authorize/integrated",
                "json",
                {
                    "username": self.settings.username,
                    "password": self.settings.password,
                },
            ),
        ]

        last_error = ""
        for url, mode, payload in attempts:
            if mode == "json":
                response = self.session.post(url, json=payload, timeout=60)
            else:
                response = self.session.post(url, data=payload, timeout=60)

            if response.status_code < 400:
                data = response.json()
                token = data.get("access_token") or data.get("APIKey")
                if token:
                    return token
                last_error = "login ok but no access_token/APIKey in response"
            else:
                last_error = f"HTTP {response.status_code}: {response.text[:300]}"

        raise SystemExit(f"Venafi login failed. Last error: {last_error}")

    def download_pkcs12(self, dest: Path, certificate_dn: str) -> Path:
        dest.parent.mkdir(parents=True, exist_ok=True)

        if self.settings.platform == "cloud":
            raise SystemExit(
                "Venafi as a Service download requires a certificate UUID. "
                "Use VENAFI_PLATFORM=tpp for Trust Protection Platform, "
                "or extend this client with the Cloud keystore API."
            )

        url = f"{self.settings.base_url}/vedsdk/Certificates/Retrieve"
        params = {
            "CertificateDN": certificate_dn,
            "Format": "PKCS #12",
            "IncludePrivateKey": "true",
            "IncludeChain": "true",
            "Password": self.settings.p12_password,
        }
        response = self.session.get(url, params=params, timeout=120)
        if response.status_code >= 400:
            raise RuntimeError(
                "Certificate download failed. "
                f"HTTP {response.status_code}: {response.text[:400]}"
            )

        dest.write_bytes(response.content)
        return dest

    def renew_certificate(self, certificate_dn: str) -> dict:
        if self.settings.platform == "cloud":
            raise SystemExit(
                "Venafi as a Service renew is not configured in this release. "
                "Use VENAFI_PLATFORM=tpp for Trust Protection Platform."
            )

        url = f"{self.settings.base_url}/vedsdk/Certificates/Renew"
        payload = {
            "CertificateDN": certificate_dn,
            "Password": self.settings.p12_password,
        }
        response = self.session.post(url, json=payload, timeout=120)
        if response.status_code >= 400:
            raise RuntimeError(
                "Certificate renew failed. "
                f"HTTP {response.status_code}: {response.text[:400]}"
            )
        try:
            return response.json()
        except ValueError:
            return {"Success": True}

    def resolve_certificate_dn(
        self,
        *,
        common_name: str,
        preferred_dn: str | None = None,
        dn_prefix: str = r"\VED\Policy\Apps",
    ) -> str:
        """Resolve Venafi Certificate DN from an optional label, then CN lookup, then prefix+CN."""
        if preferred_dn:
            return preferred_dn

        if self.settings.platform == "cloud":
            raise RuntimeError(
                f"Cannot resolve Venafi DN for CN={common_name} on Venafi Cloud. "
                f"Set Secret Manager label '{self.settings.venafi_dn_label_key}' on the cert secret."
            )

        looked_up = self.find_certificate_dn_by_cn(common_name)
        if looked_up:
            return looked_up

        prefix = dn_prefix.rstrip("\\/")
        return f"{prefix}\\{common_name}"

    def find_certificate_dn_by_cn(self, common_name: str) -> str | None:
        """Best-effort TPP/mock lookup of Certificate DN by Common Name."""
        url = f"{self.settings.base_url}/vedsdk/Certificates"
        response = self.session.get(
            url,
            params={"CN": common_name, "Limit": 25},
            timeout=60,
        )
        if response.status_code >= 400:
            return None
        try:
            data = response.json()
        except ValueError:
            return None

        certs = data.get("Certificates") or data.get("certificates") or []
        for cert in certs:
            cn = str(cert.get("CN") or cert.get("Name") or "").strip()
            dn = str(cert.get("DN") or cert.get("CertificateDN") or "").strip()
            if dn and (not cn or cn.lower() == common_name.lower()):
                return dn
        return None
