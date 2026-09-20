#!/usr/bin/env python3
"""
F5 BIG-IP Configuration Backup Script (REST API)

Backs up configurations that are NOT managed by existing Terraform modules:
  - License info
  - Hostname / Global Settings
  - Provisioning
  - Management IP / Route
  - SMTP / Syslog
  - SSL Certificates & Keys (metadata + file content)
  - SSL Profiles (Client-SSL, Server-SSL)
  - Device Management (CM Device, Device Groups, Traffic Groups, Trust Domain)
  - Failover & Sync Status

EXCLUDES (already in Terraform):
  - UCS archive, LTM objects, VLANs, Tunnels, DNS, SNMP, NTP, Auth,
    Self-IPs, Routes, Address Lists
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import requests
import urllib3

# Suppress InsecureRequestWarning for self-signed certs
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


# ---------------------------------------------------------------------------
# API endpoints to backup (category -> endpoint path)
# ---------------------------------------------------------------------------
BACKUP_ENDPOINTS = {
    "system": {
        "license":          "/mgmt/tm/sys/license",
        "global_settings":  "/mgmt/tm/sys/global-settings",
        "provision":        "/mgmt/tm/sys/provision",
        "management_ip":    "/mgmt/tm/sys/management-ip",
        "management_route": "/mgmt/tm/sys/management-route",
        "smtp":             "/mgmt/tm/sys/outbound-smtp",
        "syslog":           "/mgmt/tm/sys/syslog",
    },
    "ssl": {
        "crypto_certs":        "/mgmt/tm/sys/crypto/cert",
        "crypto_keys":         "/mgmt/tm/sys/crypto/key",
        "file_ssl_certs":      "/mgmt/tm/sys/file/ssl-cert",
        "file_ssl_keys":       "/mgmt/tm/sys/file/ssl-key",
        "profile_client_ssl":  "/mgmt/tm/ltm/profile/client-ssl",
        "profile_server_ssl":  "/mgmt/tm/ltm/profile/server-ssl",
    },
    "device_management": {
        "cm_device":        "/mgmt/tm/cm/device",
        "cm_device_group":  "/mgmt/tm/cm/device-group",
        "cm_traffic_group": "/mgmt/tm/cm/traffic-group",
        "cm_trust_domain":  "/mgmt/tm/cm/trust-domain",
        "failover_status":  "/mgmt/tm/cm/failover-status",
        "sync_status":      "/mgmt/tm/cm/sync-status",
    },
}


class F5BackupClient:
    """REST API client for F5 BIG-IP configuration backup."""

    def __init__(self, host: str, username: str, password: str, port: int = 443):
        self.base_url = f"https://{host}:{port}"
        self.username = username
        self.password = password
        self.token = None
        self.session = requests.Session()
        self.session.verify = False
        self.session.headers.update({"Content-Type": "application/json"})

    def authenticate(self) -> None:
        """Obtain an auth token via the login endpoint."""
        url = f"{self.base_url}/mgmt/shared/authn/login"
        payload = {
            "username": self.username,
            "password": self.password,
            "loginProviderName": "tmos",
        }
        resp = self.session.post(url, json=payload)
        resp.raise_for_status()

        self.token = resp.json()["token"]["token"]
        self.session.headers.update({"X-F5-Auth-Token": self.token})
        print(f"  ✓ Authenticated successfully (token obtained)")

    def get(self, endpoint: str) -> dict:
        """Send a GET request to the given endpoint."""
        url = f"{self.base_url}{endpoint}"
        resp = self.session.get(url)
        resp.raise_for_status()
        return resp.json()

    def run_bash(self, command: str) -> str:
        """Execute a bash command on the device via the util/bash endpoint."""
        url = f"{self.base_url}/mgmt/tm/util/bash"
        payload = {
            "command": "run",
            "utilCmdArgs": f'-c "{command}"',
        }
        resp = self.session.post(url, json=payload)
        resp.raise_for_status()
        result = resp.json()
        return result.get("commandResult", "")


def backup_endpoints(client: F5BackupClient, output_dir: Path) -> dict:
    """Query all backup endpoints and save responses as JSON files."""
    summary = {}

    for category, endpoints in BACKUP_ENDPOINTS.items():
        cat_dir = output_dir / category
        cat_dir.mkdir(parents=True, exist_ok=True)

        for name, endpoint in endpoints.items():
            print(f"  Fetching {category}/{name} ...", end=" ")
            try:
                data = client.get(endpoint)
                filepath = cat_dir / f"{name}.json"
                filepath.write_text(json.dumps(data, indent=2), encoding="utf-8")
                summary[f"{category}/{name}"] = "✓ OK"
                print("✓")
            except requests.exceptions.HTTPError as e:
                summary[f"{category}/{name}"] = f"✗ {e.response.status_code}"
                print(f"✗ HTTP {e.response.status_code}")
            except Exception as e:
                summary[f"{category}/{name}"] = f"✗ {str(e)}"
                print(f"✗ {e}")

    return summary


def backup_ssl_files(client: F5BackupClient, output_dir: Path) -> dict:
    """Download actual SSL certificate and key file contents from the device."""
    ssl_dir = output_dir / "ssl" / "files"
    ssl_dir.mkdir(parents=True, exist_ok=True)
    summary = {}

    # Get list of certificate files
    print("\n  Downloading SSL certificate files...")
    try:
        cert_list_output = client.run_bash("ls -1 /config/ssl/ssl.crt/ 2>/dev/null")
        cert_files = [
            f.strip()
            for f in cert_list_output.strip().split("\n")
            if f.strip() and f.strip().endswith((".crt", ".pem"))
        ]

        for cert_file in cert_files:
            print(f"    Downloading cert: {cert_file} ...", end=" ")
            try:
                content = client.run_bash(f"cat /config/ssl/ssl.crt/{cert_file}")
                if content and "-----BEGIN" in content:
                    cert_dir = ssl_dir / "certs"
                    cert_dir.mkdir(parents=True, exist_ok=True)
                    (cert_dir / cert_file).write_text(content, encoding="utf-8")
                    summary[f"cert/{cert_file}"] = "✓ OK"
                    print("✓")
                else:
                    summary[f"cert/{cert_file}"] = "✗ Empty or binary"
                    print("✗ Empty/binary")
            except Exception as e:
                summary[f"cert/{cert_file}"] = f"✗ {e}"
                print(f"✗ {e}")
    except Exception as e:
        summary["cert_listing"] = f"✗ {e}"
        print(f"  ✗ Failed to list certs: {e}")

    # Get list of key files
    print("\n  Downloading SSL key files...")
    try:
        key_list_output = client.run_bash("ls -1 /config/ssl/ssl.key/ 2>/dev/null")
        key_files = [
            f.strip()
            for f in key_list_output.strip().split("\n")
            if f.strip() and f.strip().endswith((".key", ".pem"))
        ]

        for key_file in key_files:
            print(f"    Downloading key: {key_file} ...", end=" ")
            try:
                content = client.run_bash(f"cat /config/ssl/ssl.key/{key_file}")
                if content and "-----BEGIN" in content:
                    key_dir = ssl_dir / "keys"
                    key_dir.mkdir(parents=True, exist_ok=True)
                    (key_dir / key_file).write_text(content, encoding="utf-8")
                    summary[f"key/{key_file}"] = "✓ OK"
                    print("✓")
                else:
                    summary[f"key/{key_file}"] = "✗ Empty or binary"
                    print("✗ Empty/binary")
            except Exception as e:
                summary[f"key/{key_file}"] = f"✗ {e}"
                print(f"✗ {e}")
    except Exception as e:
        summary["key_listing"] = f"✗ {e}"
        print(f"  ✗ Failed to list keys: {e}")

    return summary


def save_summary(summary: dict, output_dir: Path) -> None:
    """Save backup summary report."""
    report = {
        "timestamp": datetime.now().isoformat(),
        "results": summary,
        "total_items": len(summary),
        "successful": sum(1 for v in summary.values() if v.startswith("✓")),
        "failed": sum(1 for v in summary.values() if v.startswith("✗")),
    }

    filepath = output_dir / "backup_summary.json"
    filepath.write_text(json.dumps(report, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="Backup F5 BIG-IP configurations via REST API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python backup_config.py --host 10.0.0.1 --username admin --password mypass
  python backup_config.py --host 10.0.0.1 --username admin --password mypass --output ./backups/dr-active
  python backup_config.py --host 10.0.0.1 --username admin --password mypass --skip-ssl-files
        """,
    )

    parser.add_argument("--host", required=True, help="BIG-IP management IP or hostname")
    parser.add_argument("--username", required=True, help="Admin username")
    parser.add_argument("--password", required=True, help="Admin password")
    parser.add_argument("--port", type=int, default=443, help="Management port (default: 443)")
    parser.add_argument(
        "--output",
        default=None,
        help="Output directory (default: ./backup_<host>_<timestamp>)",
    )
    parser.add_argument(
        "--skip-ssl-files",
        action="store_true",
        help="Skip downloading actual SSL cert/key file contents",
    )

    args = parser.parse_args()

    # Create output directory
    if args.output:
        output_dir = Path(args.output)
    else:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = Path(f"./backup_{args.host}_{timestamp}")

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*60}")
    print(f"F5 BIG-IP Configuration Backup")
    print(f"{'='*60}")
    print(f"  Host:   {args.host}:{args.port}")
    print(f"  User:   {args.username}")
    print(f"  Output: {output_dir.resolve()}")
    print(f"{'='*60}\n")

    # Initialize client
    client = F5BackupClient(args.host, args.username, args.password, args.port)

    # Step 1: Authenticate
    print("[1/3] Authenticating...")
    try:
        client.authenticate()
    except Exception as e:
        print(f"\n  ✗ Authentication failed: {e}")
        print("  Check host, username, and password.")
        sys.exit(1)

    # Step 2: Backup API endpoints
    print("\n[2/3] Backing up configurations...")
    summary = backup_endpoints(client, output_dir)

    # Step 3: Backup SSL files
    ssl_summary = {}
    if not args.skip_ssl_files:
        print("\n[3/3] Backing up SSL certificate & key files...")
        ssl_summary = backup_ssl_files(client, output_dir)
    else:
        print("\n[3/3] Skipping SSL file download (--skip-ssl-files)")

    # Save summary
    all_summary = {**summary, **ssl_summary}
    save_summary(all_summary, output_dir)

    # Print final report
    successful = sum(1 for v in all_summary.values() if v.startswith("✓"))
    failed = sum(1 for v in all_summary.values() if v.startswith("✗"))

    print(f"\n{'='*60}")
    print(f"  Backup Complete!")
    print(f"  Output:     {output_dir.resolve()}")
    print(f"  Successful: {successful}")
    print(f"  Failed:     {failed}")
    print(f"  Total:      {len(all_summary)}")
    print(f"{'='*60}\n")

    if failed > 0:
        print("  Failed items:")
        for name, status in all_summary.items():
            if status.startswith("✗"):
                print(f"    - {name}: {status}")
        print()

    # Exit with error code if any failures
    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
