# F5 BIG-IP LTM — Complete Wipe & Rebuild Runbook

> **Audience**: DevOps / Network Engineering Team  
> **Scope**: CLI (TMSH) and REST API commands only  
> **Environment**: 4× Physical Appliances, TMOS v21.1.x, DC + DR (Active/Standby each)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Pre-Reset: Backup Configurations](#2-pre-reset-backup-configurations)
3. [Factory Reset Procedure](#3-factory-reset-procedure)
4. [Install Declarative Onboarding (DO)](#4-install-declarative-onboarding-do)
5. [Bootstrap with Terraform (bigip_do)](#5-bootstrap-with-terraform-bigip_do)
6. [SSL Certificate Management](#6-ssl-certificate-management)
7. [HA Setup — Device Trust, Sync & Failover](#7-ha-setup--device-trust-sync--failover)
8. [Verification & Validation](#8-verification--validation)
9. [Troubleshooting](#9-troubleshooting)
10. [References & Links](#10-references--links)

---

## 1. Architecture Overview

```
                    ┌──────────────────────────────────────────────────┐
                    │               F5 BIG-IP LTM Fleet               │
                    │                                                  │
    Data Center (DC)                          Disaster Recovery (DR)
   ┌──────────────────────┐                  ┌──────────────────────┐
   │  Box1         Box2   │                  │  Box3         Box4   │
   │  ACTIVE    STANDBY   │                  │  ACTIVE    STANDBY   │
   │  ┌──────┐  ┌──────┐  │                  │  ┌──────┐  ┌──────┐  │
   │  │Mgmt: │  │Mgmt: │  │                  │  │Mgmt: │  │Mgmt: │  │
   │  │<IP1> │  │<IP2> │  │                  │  │<IP3> │  │<IP4> │  │
   │  └──┬───┘  └──┬───┘  │                  │  └──┬───┘  └──┬───┘  │
   │     │  ConfigSync  │  │                  │     │  ConfigSync  │  │
   │     └──────────────┘  │                  │     └──────────────┘  │
   └──────────────────────┘                  └──────────────────────┘

   Execution Order: DR first → then DC
   Within each pair: Standby first → then Active (with HA config)
```

### Automation Pipeline

```
Step 1: Backup          →  Python script via REST API
Step 2: Factory Reset   →  TMSH command (SSH required)
Step 3: Install DO RPM  →  REST API
Step 4: Bootstrap (DO)  →  Terraform (bigip_do resource)
Step 5: SSL Certs       →  Terraform (bigip_ssl_certificate / bigip_ssl_key)
Step 6: LTM Objects     →  Existing Terraform modules
Step 7: Verify          →  REST API / TMSH
```

---

## 2. Pre-Reset: Backup Configurations

### 2.1 What to Backup

Items we **DO NOT** have in existing Terraform and must capture before reset:

| Category | API Endpoint | TMSH Command |
|----------|-------------|--------------|
| **License** | `GET /mgmt/tm/sys/license` | `tmsh show sys license` |
| **Hostname** | `GET /mgmt/tm/sys/global-settings` | `tmsh list sys global-settings hostname` |
| **Provisioning** | `GET /mgmt/tm/sys/provision` | `tmsh list sys provision` |
| **Management IP** | `GET /mgmt/tm/sys/management-ip` | `tmsh list sys management-ip` |
| **Management Route** | `GET /mgmt/tm/sys/management-route` | `tmsh list sys management-route` |
| **SMTP** | `GET /mgmt/tm/sys/outbound-smtp` | `tmsh list sys outbound-smtp` |
| **Syslog** | `GET /mgmt/tm/sys/syslog` | `tmsh list sys syslog` |
| **SSL Certificates** | `GET /mgmt/tm/sys/crypto/cert` | `tmsh list sys crypto cert` |
| **SSL Keys** | `GET /mgmt/tm/sys/crypto/key` | `tmsh list sys crypto key` |
| **SSL File Certs** | `GET /mgmt/tm/sys/file/ssl-cert` | `tmsh list sys file ssl-cert` |
| **SSL File Keys** | `GET /mgmt/tm/sys/file/ssl-key` | `tmsh list sys file ssl-key` |
| **Client-SSL Profiles** | `GET /mgmt/tm/ltm/profile/client-ssl` | `tmsh list ltm profile client-ssl` |
| **Server-SSL Profiles** | `GET /mgmt/tm/ltm/profile/server-ssl` | `tmsh list ltm profile server-ssl` |
| **Device Config** | `GET /mgmt/tm/cm/device` | `tmsh list cm device` |
| **Device Groups** | `GET /mgmt/tm/cm/device-group` | `tmsh list cm device-group` |
| **Traffic Groups** | `GET /mgmt/tm/cm/traffic-group` | `tmsh list cm traffic-group` |
| **Trust Domain** | `GET /mgmt/tm/cm/trust-domain` | `tmsh list cm trust-domain` |
| **Failover Status** | `GET /mgmt/tm/cm/failover-status` | `tmsh show cm failover-status` |
| **Sync Status** | `GET /mgmt/tm/cm/sync-status` | `tmsh show cm sync-status` |

### 2.2 Backup via REST API

All API calls use Basic Auth or Token Auth. Token auth is recommended for multiple requests.

#### Get Auth Token

```bash
# Request auth token (valid for 1200 seconds by default)
curl -sk \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/shared/authn/login \
  -d '{"username":"admin","password":"<PASSWORD>","loginProviderName":"tmos"}'

# Response contains: { "token": { "token": "<TOKEN_VALUE>" } }
# Use in subsequent requests:
#   -H "X-F5-Auth-Token: <TOKEN_VALUE>"
```

#### Backup License

```bash
# API
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/license

# CLI
tmsh show sys license
tmsh show sys license | grep "Registration Key"

# Also save the license file directly
cat /config/bigip.license
```

#### Backup System Settings

```bash
# API — Hostname
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/global-settings \
  | python3 -m json.tool

# API — Provisioning
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/provision

# API — Management IP
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/management-ip

# API — Management Route
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/management-route

# API — SMTP
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/outbound-smtp

# API — Syslog
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/syslog
```

```bash
# CLI equivalents
tmsh list sys global-settings hostname
tmsh list sys provision
tmsh list sys management-ip
tmsh list sys management-route
tmsh list sys outbound-smtp
tmsh list sys syslog
```

#### Backup SSL Certificates & Keys

```bash
# API — List certificate metadata
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/crypto/cert

# API — List key metadata
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/crypto/key

# API — List SSL file objects (certificates)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/file/ssl-cert

# API — List SSL file objects (keys)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/file/ssl-key

# API — Download certificate file content via bash utility
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/util/bash \
  -d '{"command":"run","utilCmdArgs":"-c \"cat /config/ssl/ssl.crt/<CERT_NAME>.crt\""}'

# API — Download key file content via bash utility
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/util/bash \
  -d '{"command":"run","utilCmdArgs":"-c \"cat /config/ssl/ssl.key/<KEY_NAME>.key\""}'

# API — List Client-SSL profiles
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/ltm/profile/client-ssl

# API — List Server-SSL profiles
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/ltm/profile/server-ssl
```

```bash
# CLI — List certs and keys
tmsh list sys crypto cert
tmsh list sys crypto key
tmsh list sys file ssl-cert
tmsh list sys file ssl-key

# CLI — Copy cert/key files for backup
mkdir -p /var/tmp/ssl-backup
cp /config/ssl/ssl.crt/* /var/tmp/ssl-backup/
cp /config/ssl/ssl.key/* /var/tmp/ssl-backup/
cd /var/tmp && tar czf ssl-backup-$(date +%Y%m%d).tar.gz ssl-backup/
# SCP the tarball off the device

# CLI — List SSL profiles
tmsh list ltm profile client-ssl
tmsh list ltm profile server-ssl
```

#### Backup Device Management / HA Configuration

```bash
# API — Device settings (configsync IP, failover IPs, mirror IP)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/device

# API — Device groups
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/device-group

# API — Traffic groups
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/traffic-group

# API — Trust domain
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/trust-domain

# API — Failover status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/failover-status

# API — Sync status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/sync-status
```

```bash
# CLI equivalents
tmsh list cm device
tmsh list cm device-group
tmsh list cm traffic-group
tmsh list cm trust-domain
tmsh show cm failover-status
tmsh show cm sync-status
```

### 2.3 Automated Backup Script

Use the provided Python script to automate the backup:

```bash
# Install dependencies
pip install -r scripts/requirements.txt

# Run backup for each device
python scripts/backup_config.py \
  --host <MGMT_IP> \
  --username admin \
  --password <PASSWORD> \
  --output ./backups/dr-active

python scripts/backup_config.py \
  --host <MGMT_IP_2> \
  --username admin \
  --password <PASSWORD> \
  --output ./backups/dr-standby
```

---

## 3. Factory Reset Procedure

> **Reference**: [K13127 — Resetting the BIG-IP configuration to factory defaults](https://my.f5.com/manage/s/article/K13127)

### 3.1 What the Reset Does

| Aspect | After `load sys config default` |
|--------|-------------------------------|
| Management IP | **Preserved** |
| License | **Preserved** |
| Admin/root passwords | **Preserved** |
| iControl LX packages (AS3, DO, TS) | **Preserved** |
| VLANs, Self-IPs, Routes | **Removed** |
| All LTM objects (VS, Pools, etc.) | **Removed** |
| Hostname, DNS, NTP, SMTP | **Reset to defaults** |
| SSL certificates (in /config/ssl/) | **Removed** (except device cert) |
| Device Trust / Device Groups | **Removed** |
| ConfigSync / Failover settings | **Removed** |

### 3.2 Pre-Reset Checklist

- [ ] UCS backups downloaded from **all** devices
- [ ] SSL certs/keys backed up (files + metadata)
- [ ] License registration keys noted
- [ ] Management IPs and gateways documented
- [ ] Backup script output saved securely
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified — **complete traffic outage during reset**
- [ ] Console/serial access available as fallback

### 3.3 Reset Commands

**Execute on STANDBY device first, then ACTIVE.**

#### CLI (TMSH) — Primary Method

```bash
# Step 1: Disable HA sync (if still partially working)
tmsh modify cm device-group <DEVICE_GROUP_NAME> auto-sync disabled
tmsh save sys config

# Step 2: Break device trust
tmsh delete cm trust-domain all

# Step 3: Factory reset
tmsh load sys config default
# Confirm with 'y' when prompted

# Step 4: Save clean config to disk
tmsh save sys config

# Step 5: Clear MCPd transaction cache (prevents future sync issues)
tmsh restart sys service mcpd
# Wait 60-90 seconds for mcpd to restart

# Step 6: Verify clean state
tmsh list ltm virtual            # Should be empty
tmsh list net vlan               # Should be empty
tmsh list net self               # Should be empty
tmsh show sys license | grep "Registration Key"  # Should show key
tmsh list sys management-ip      # Should show management IP
```

#### REST API — Alternative (if no SSH access)

```bash
# Step 1: Disable HA sync
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X PATCH https://<MGMT_IP>/mgmt/tm/cm/device-group/<DEVICE_GROUP_NAME> \
  -d '{"autoSync":"disabled"}'

# Step 2: Factory reset via bash utility
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/util/bash \
  -d '{"command":"run","utilCmdArgs":"-c \"tmsh load sys config default <<< y\""}'

# Step 3: Save config
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/sys/config \
  -d '{"command":"save"}'

# Step 4: Restart mcpd
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/sys/service \
  -d '{"command":"restart","name":"mcpd"}'

# Wait 90 seconds, then verify
sleep 90

# Step 5: Verify clean state
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/ltm/virtual
# Should return empty items array

curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/global-settings \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('hostname',''))"
# Should show default hostname
```

### 3.4 Reset Sequence (All 4 Boxes)

```
1. DR Standby (Box 4)  →  Reset  →  Verify clean state
2. DR Active  (Box 3)  →  Reset  →  Verify clean state
3. DC Standby (Box 2)  →  Reset  →  Verify clean state
4. DC Active  (Box 1)  →  Reset  →  Verify clean state
```

---

## 4. Install Declarative Onboarding (DO)

> **What is DO?** F5 Declarative Onboarding is an iControl LX extension that provides a declarative (JSON-based) interface for initial BIG-IP device configuration — licensing, system settings, networking, and HA setup in a single API call.

### 4.1 Download DO RPM

- **GitHub Releases**: https://github.com/F5Networks/f5-declarative-onboarding/releases
- **Compatibility Matrix**: https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/revision-history.html
- Download RPM compatible with TMOS v21.1.x

### 4.2 Install via REST API

```bash
# Step 1: Upload RPM to the device
FILENAME="f5-declarative-onboarding-1.44.0-2.noarch.rpm"
FILESIZE=$(stat -f%z "$FILENAME" 2>/dev/null || stat --printf='%s' "$FILENAME")

curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/octet-stream" \
  -H "Content-Range: 0-$((FILESIZE-1))/$FILESIZE" \
  -H "Content-Length: $FILESIZE" \
  -X POST "https://<MGMT_IP>/mgmt/shared/file-transfer/uploads/$FILENAME" \
  --data-binary "@$FILENAME"

# Step 2: Install the RPM
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/shared/iapp/package-management-tasks \
  -d "{\"operation\":\"INSTALL\",\"packageFilePath\":\"/var/config/rest/downloads/$FILENAME\"}"

# Step 3: Check installation status (poll until FINISHED)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/iapp/package-management-tasks/<TASK_ID>

# Step 4: Verify DO is available
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/declarative-onboarding/info
```

### 4.3 Install via CLI

```bash
# SCP the RPM to the device
scp $FILENAME admin@<MGMT_IP>:/var/tmp/

# SSH to device and install via REST (localhost)
curl -sku admin:<PASSWORD> \
  -X POST https://localhost/mgmt/shared/iapp/package-management-tasks \
  -H "Content-Type: application/json" \
  -d '{"operation":"INSTALL","packageFilePath":"/var/tmp/f5-declarative-onboarding-1.44.0-2.noarch.rpm"}'

# Verify
curl -sku admin:<PASSWORD> \
  https://localhost/mgmt/shared/declarative-onboarding/info
```

### 4.4 Verify Installed Packages

```bash
# API — List all iControl LX packages
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/iapp/package-management-tasks \
  -d '{"operation":"QUERY"}'

# CLI
ls /var/config/rest/iapps/
```

---

## 5. Bootstrap with Terraform (bigip_do)

### 5.1 Terraform Resource: `bigip_do`

The `bigip_do` resource in the F5 Terraform provider sends a DO declaration to configure a BIG-IP device.

```hcl
resource "bigip_do" "this" {
  do_json    = jsonencode(local.do_declaration)  # DO JSON string
  timeout    = 30                                 # minutes
}
```

**Provider Reference**: https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/bigip_do

### 5.2 DO Declaration Schema

Full schema reference: https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html

**Supported classes in DO:**

| Class | Purpose |
|-------|---------|
| `System` | Hostname, console timeout, auto-phonehome |
| `License` | Registration key, add-on keys |
| `Provision` | Module provisioning (LTM, ASM, etc.) |
| `DNS` | Name servers, search domains |
| `NTP` | NTP servers, timezone |
| `User` | Local user accounts |
| `VLAN` | VLAN configuration |
| `SelfIp` | Self-IP addresses |
| `Route` | Static routes |
| `RouteDomain` | Route domain configuration |
| `ConfigSync` | Config sync IP |
| `FailoverUnicast` | Failover unicast address |
| `FailoverMulticast` | Failover multicast settings |
| `MirrorIp` | Connection mirroring IPs |
| `DeviceTrust` | Establish device trust with peer |
| `DeviceGroup` | Create sync-failover device group |
| `TrafficGroup` | Traffic group configuration |
| `Trunk` | Interface trunking |
| `ManagementRoute` | Management network routes |
| `SyslogRemoteServer` | Remote syslog destinations |
| `SnmpAgent` | SNMP agent configuration |
| `SnmpTrapDestination` | SNMP trap destinations |
| `SnmpCommunity` | SNMP community strings |
| `HTTPD` | HTTP daemon settings |
| `SSHD` | SSH daemon settings |
| `DbVariables` | System DB variable overrides |

### 5.3 Bootstrap Execution Order

```
1. terraform apply (DR environment)
   ├── Module: standby_bootstrap  →  DO declaration WITHOUT DeviceTrust/DeviceGroup
   │     └── Configures: License, Hostname, DNS, NTP, Provisioning,
   │         VLANs, Self-IPs, Routes, ConfigSync IP, Failover Address
   │
   └── Module: active_bootstrap   →  DO declaration WITH DeviceTrust/DeviceGroup
         ├── depends_on: standby_bootstrap
         └── Configures: Same as standby + DeviceTrust, DeviceGroup,
             TrafficGroup, Initial Sync
```

### 5.4 POST DO Declaration Directly (API)

If you need to apply DO without Terraform:

```bash
# POST declaration to a device
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/shared/declarative-onboarding \
  -d @do-declaration.json

# Check status (DO is async)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/declarative-onboarding/task/<TASK_ID>

# Get current DO configuration
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/declarative-onboarding

# Get DO status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/declarative-onboarding/info
```

---

## 6. SSL Certificate Management

### 6.1 Import Certificates via REST API

```bash
# Step 1: Upload certificate file
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/octet-stream" \
  -X POST https://<MGMT_IP>/mgmt/shared/file-transfer/uploads/my-app.crt \
  --data-binary @my-app.crt

# Step 2: Install certificate from uploaded file
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/sys/crypto/cert \
  -d '{
    "command": "install",
    "name": "my-app-cert",
    "from-local-file": "/var/config/rest/downloads/my-app.crt"
  }'

# Step 3: Upload key file
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/octet-stream" \
  -X POST https://<MGMT_IP>/mgmt/shared/file-transfer/uploads/my-app.key \
  --data-binary @my-app.key

# Step 4: Install key from uploaded file
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/sys/crypto/key \
  -d '{
    "command": "install",
    "name": "my-app-cert",
    "from-local-file": "/var/config/rest/downloads/my-app.key"
  }'
```

### 6.2 Import Certificates via CLI

```bash
# Copy files to device (via SCP)
scp my-app.crt admin@<MGMT_IP>:/var/tmp/
scp my-app.key admin@<MGMT_IP>:/var/tmp/

# Install certificate
tmsh install sys crypto cert my-app-cert from-local-file /var/tmp/my-app.crt

# Install key
tmsh install sys crypto key my-app-cert from-local-file /var/tmp/my-app.key

# Verify
tmsh list sys crypto cert my-app-cert
tmsh list sys crypto key my-app-cert

# Save
tmsh save sys config
```

### 6.3 Create SSL Profiles

```bash
# API — Create Client-SSL profile
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/ltm/profile/client-ssl \
  -d '{
    "name": "my-app-clientssl",
    "partition": "Common",
    "defaultsFrom": "/Common/clientssl",
    "certKeyChain": [{
      "name": "default",
      "cert": "/Common/my-app-cert.crt",
      "key": "/Common/my-app-cert.key"
    }]
  }'

# API — Create Server-SSL profile
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<MGMT_IP>/mgmt/tm/ltm/profile/server-ssl \
  -d '{
    "name": "my-app-serverssl",
    "partition": "Common",
    "defaultsFrom": "/Common/serverssl"
  }'
```

```bash
# CLI — Create Client-SSL profile
tmsh create ltm profile client-ssl /Common/my-app-clientssl \
  defaults-from /Common/clientssl \
  cert-key-chain add { default { cert /Common/my-app-cert.crt key /Common/my-app-cert.key } }

# CLI — Create Server-SSL profile
tmsh create ltm profile server-ssl /Common/my-app-serverssl \
  defaults-from /Common/serverssl

tmsh save sys config
```

### 6.4 Import Certificates via Terraform

```hcl
resource "bigip_ssl_certificate" "app" {
  name      = "my-app-cert"
  content   = file("${path.module}/certs/my-app.crt")
  partition = "Common"
}

resource "bigip_ssl_key" "app" {
  name      = "my-app-cert"
  content   = file("${path.module}/certs/my-app.key")
  partition = "Common"
}

resource "bigip_ltm_profile_client_ssl" "app" {
  name          = "/Common/my-app-clientssl"
  defaults_from = "/Common/clientssl"
  cert          = "/Common/my-app-cert.crt"
  key           = "/Common/my-app-cert.key"
}
```

---

## 7. HA Setup — Device Trust, Sync & Failover

> **Note**: If using DO (Declarative Onboarding), HA is configured automatically as part of the DO declaration on the Active box. The commands below are for manual/standalone HA setup.

### 7.1 Set ConfigSync IP (on BOTH devices)

```bash
# API — Box 1
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X PATCH https://<BOX1_MGMT_IP>/mgmt/tm/cm/device/<BOX1_HOSTNAME> \
  -d '{"configsyncIp":"<BOX1_HA_SELF_IP>"}'

# API — Box 2
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X PATCH https://<BOX2_MGMT_IP>/mgmt/tm/cm/device/<BOX2_HOSTNAME> \
  -d '{"configsyncIp":"<BOX2_HA_SELF_IP>"}'
```

```bash
# CLI — Box 1
tmsh modify cm device <BOX1_HOSTNAME> configsync-ip <BOX1_HA_SELF_IP>

# CLI — Box 2
tmsh modify cm device <BOX2_HOSTNAME> configsync-ip <BOX2_HA_SELF_IP>
```

### 7.2 Set Failover Unicast Address (on BOTH devices)

```bash
# API — Box 1
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X PATCH https://<BOX1_MGMT_IP>/mgmt/tm/cm/device/<BOX1_HOSTNAME> \
  -d '{"unicastAddress":[{"effectiveIp":"<BOX1_HA_SELF_IP>","effectivePort":1026,"ip":"<BOX1_HA_SELF_IP>"}]}'

# CLI — Box 1
tmsh modify cm device <BOX1_HOSTNAME> \
  unicast-address { { effective-ip <BOX1_HA_SELF_IP> effective-port 1026 ip <BOX1_HA_SELF_IP> } }
```

### 7.3 Set Mirror IP (on BOTH devices)

```bash
# API — Box 1
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X PATCH https://<BOX1_MGMT_IP>/mgmt/tm/cm/device/<BOX1_HOSTNAME> \
  -d '{"mirrorIp":"<BOX1_HA_SELF_IP>","mirrorSecondaryIp":"<BOX1_INTERNAL_SELF_IP>"}'

# CLI — Box 1
tmsh modify cm device <BOX1_HOSTNAME> \
  mirror-ip <BOX1_HA_SELF_IP> mirror-secondary-ip <BOX1_INTERNAL_SELF_IP>
```

### 7.4 Establish Device Trust (from ACTIVE device only)

```bash
# API — Run from Box 1 (Active), adds Box 2 (Standby) to trust
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<BOX1_MGMT_IP>/mgmt/tm/cm/add-to-trust \
  -d '{
    "command": "run",
    "name": "Root",
    "caDevice": true,
    "device": "<BOX2_MGMT_IP>",
    "deviceName": "<BOX2_HOSTNAME>",
    "username": "admin",
    "password": "<BOX2_ADMIN_PASSWORD>"
  }'

# Verify trust
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<BOX1_MGMT_IP>/mgmt/tm/cm/trust-domain
```

```bash
# CLI — Run from Box 1 (Active)
tmsh modify cm trust-domain Root ca-devices add \
  { <BOX2_MGMT_IP> } name <BOX2_HOSTNAME> \
  username admin password "<BOX2_ADMIN_PASSWORD>"

# Verify trust
tmsh show cm trust-domain
```

### 7.5 Create Device Group (from ACTIVE device)

```bash
# API
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<BOX1_MGMT_IP>/mgmt/tm/cm/device-group \
  -d '{
    "name": "<DEVICE_GROUP_NAME>",
    "type": "sync-failover",
    "autoSync": "enabled",
    "networkFailover": "enabled",
    "devices": [
      {"name": "<BOX1_HOSTNAME>"},
      {"name": "<BOX2_HOSTNAME>"}
    ]
  }'
```

```bash
# CLI
tmsh create cm device-group <DEVICE_GROUP_NAME> \
  type sync-failover \
  devices add { <BOX1_HOSTNAME> <BOX2_HOSTNAME> } \
  auto-sync enabled \
  network-failover enabled
```

### 7.6 Initial Sync (from ACTIVE device)

```bash
# API
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<BOX1_MGMT_IP>/mgmt/tm/cm \
  -d '{"command":"run","utilCmdArgs":"config-sync to-group <DEVICE_GROUP_NAME>"}'

# Check sync status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<BOX1_MGMT_IP>/mgmt/tm/cm/sync-status
```

```bash
# CLI
tmsh run cm config-sync to-group <DEVICE_GROUP_NAME>

# Check status
tmsh show cm sync-status
# Expected: "In Sync"
```

---

## 8. Verification & Validation

### 8.1 Post-Bootstrap Checks

```bash
# API — Check hostname
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/global-settings \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])"

# API — Check license
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/license

# API — Check provisioning
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/sys/provision

# API — Check VLANs
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/net/vlan

# API — Check Self-IPs
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/net/self

# API — Check HA sync status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/sync-status

# API — Check failover status
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/tm/cm/failover-status
```

```bash
# CLI equivalents
tmsh list sys global-settings hostname
tmsh show sys license | grep "Registration Key"
tmsh list sys provision
tmsh list net vlan
tmsh list net self
tmsh show cm sync-status
tmsh show cm failover-status
```

### 8.2 Config Parity Check (Compare Both Devices)

```bash
# API — Compare VS count
BOX1_COUNT=$(curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<BOX1>/mgmt/tm/ltm/virtual \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('items',[])))")

BOX2_COUNT=$(curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<BOX2>/mgmt/tm/ltm/virtual \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('items',[])))")

echo "Box1: $BOX1_COUNT VS | Box2: $BOX2_COUNT VS"
[ "$BOX1_COUNT" -eq "$BOX2_COUNT" ] && echo "✅ MATCH" || echo "❌ MISMATCH"
```

### 8.3 Failover Test

```bash
# API — Force active device to standby
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<ACTIVE_MGMT_IP>/mgmt/tm/sys \
  -d '{"command":"run","utilCmdArgs":"failover standby"}'

# Verify peer is now active
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<STANDBY_MGMT_IP>/mgmt/tm/cm/failover-status

# Restore original active (force peer back to standby)
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -X POST https://<STANDBY_MGMT_IP>/mgmt/tm/sys \
  -d '{"command":"run","utilCmdArgs":"failover standby"}'
```

```bash
# CLI
tmsh run sys failover standby     # on active device
tmsh show cm failover-status      # on both devices
```

---

## 9. Troubleshooting

### DO Declaration Fails

```bash
# Check DO task status and error messages
curl -sk -H "X-F5-Auth-Token: <TOKEN>" \
  https://<MGMT_IP>/mgmt/shared/declarative-onboarding/task

# Check restjavad logs (DO runs as part of restjavad)
# CLI
tail -f /var/log/restjavad/restjavad.0.log | grep -i "declarative\|error"

# Restart restjavad if DO is unresponsive
tmsh restart sys service restjavad
```

### Sync Issues After Bootstrap

```bash
# Check sync details
tmsh show cm sync-status verbose

# Force full sync if incremental fails
tmsh run cm config-sync force-full-load-push to-group <GROUP_NAME>

# Check MCPd status
tmsh show sys service mcpd

# Check config generation ID mismatch
tmsh show cm device field-fmt | grep generation
```

### License Issues

```bash
# Re-activate license (online)
tmsh install sys license registration-key <REG_KEY>

# Check license status
tmsh show sys license
```

---

## 10. References & Links

| Resource | URL |
|----------|-----|
| **DO Documentation** | https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/ |
| **DO Schema Reference** | https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html |
| **DO GitHub & Releases** | https://github.com/F5Networks/f5-declarative-onboarding/releases |
| **DO Composing a Declaration** | https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/composing-a-declaration.html |
| **DO Clustering (HA) Examples** | https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/clustering.html |
| **Terraform bigip_do** | https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/bigip_do |
| **Terraform F5 Provider** | https://registry.terraform.io/providers/F5Networks/bigip/latest/docs |
| **K13127 — Factory Reset** | https://my.f5.com/manage/s/article/K13127 |
| **iControl REST API Reference** | https://clouddocs.f5.com/api/icontrol-rest/ |
| **AS3 Documentation** | https://clouddocs.f5.com/products/extensions/f5-appsvcs-extension/latest/ |
