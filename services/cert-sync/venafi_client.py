from __future__ import annotations

from pathlib import Path

import requests

from config import Settings


class VenafiClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.session = requests.Session()
        self.session.verify = settings.tls_verify

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

    def download_pkcs12(self, dest: Path) -> Path:
        dest.parent.mkdir(parents=True, exist_ok=True)

        if self.settings.platform == "cloud":
            raise SystemExit(
                "Venafi as a Service download requires a certificate UUID. "
                "Use VENAFI_PLATFORM=tpp for Trust Protection Platform, "
                "or extend this client with the Cloud keystore API."
            )

        url = f"{self.settings.base_url}/vedsdk/Certificates/Retrieve"
        params = {
            "CertificateDN": self.settings.certificate_dn,
            "Format": "PKCS #12",
            "IncludePrivateKey": "true",
            "IncludeChain": "true",
            "Password": self.settings.p12_password,
        }
        response = self.session.get(url, params=params, timeout=120)
        if response.status_code >= 400:
            raise SystemExit(
                "Certificate download failed. "
                f"HTTP {response.status_code}: {response.text[:400]}"
            )

        dest.write_bytes(response.content)
        return dest

    def renew_certificate(self) -> dict:
        if self.settings.platform == "cloud":
            raise SystemExit(
                "Venafi as a Service renew is not configured in this release. "
                "Use VENAFI_PLATFORM=tpp for Trust Protection Platform."
            )

        url = f"{self.settings.base_url}/vedsdk/Certificates/Renew"
        payload = {
            "CertificateDN": self.settings.certificate_dn,
            "Password": self.settings.p12_password,
        }
        response = self.session.post(url, json=payload, timeout=120)
        if response.status_code >= 400:
            raise SystemExit(
                "Certificate renew failed. "
                f"HTTP {response.status_code}: {response.text[:400]}"
            )
        try:
            return response.json()
        except ValueError:
            return {"Success": True}

    def fetch_certificate_meta(self) -> dict:
        if self.settings.platform == "cloud":
            return {"dn": self.settings.certificate_dn}

        url = f"{self.settings.base_url}/vedsdk/Certificates"
        params = {"CN": self.settings.certificate_dn.split("\\")[-1]}
        try:
            response = self.session.get(url, params=params, timeout=60)
            if response.status_code >= 400:
                return {"dn": self.settings.certificate_dn}
            data = response.json()
            certs = data.get("Certificates") or data.get("certificates") or []
            if not certs:
                return {"dn": self.settings.certificate_dn}
            first = certs[0]
            return {
                "dn": first.get("DN") or self.settings.certificate_dn,
                "name": first.get("Name") or first.get("CN"),
                "valid_to": first.get("ValidTo") or first.get("X509", {}).get("ValidTo"),
            }
        except requests.RequestException:
            return {"dn": self.settings.certificate_dn}
