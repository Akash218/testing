# F5 BIG-IP LTM — End-to-End Bootstrap Automation

Complete automation for wiping and rebuilding F5 BIG-IP LTM Active/Standby HA pairs from scratch.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                ENVIRONMENTS                      │
│                                                  │
│   DC (Data Center)          DR (Disaster Recovery)│
│   ┌─────────┐ ┌─────────┐  ┌─────────┐ ┌─────────┐│
│   │ Active  │ │ Standby │  │ Active  │ │ Standby ││
│   │ Box 1   │ │ Box 2   │  │ Box 3   │ │ Box 4   ││
│   └─────────┘ └─────────┘  └─────────┘ └─────────┘│
│                                                  │
│   4 Physical Appliances, TMOS v21.1.x            │
└─────────────────────────────────────────────────┘
```

## Project Structure

```
├── docs/
│   └── f5-bootstrap-runbook.md         # Full runbook (CLI + API commands)
├── scripts/
│   ├── backup_config.py                # Pre-reset backup script (REST API)
│   └── requirements.txt               # Python dependencies
├── terraform/
│   ├── modules/
│   │   └── f5-bootstrap/               # Reusable DO bootstrap module
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── versions.tf
│   └── environments/
│       ├── dr/                          # DR environment (start here)
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── providers.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars.example
│       └── dc/                          # DC environment
│           ├── main.tf
│           ├── variables.tf
│           ├── providers.tf
│           ├── outputs.tf
│           └── terraform.tfvars.example
```

## Workflow

1. **Backup** — `python scripts/backup_config.py` (captures license, SSL, device mgmt configs)
2. **Reset** — `tmsh load sys config default` on both boxes ([K13127](https://my.f5.com/manage/s/article/K13127))
3. **Bootstrap** — `cd terraform/environments/dr && terraform apply` (provisions both boxes via DO)
4. **LTM Config** — Apply existing Terraform modules (monitors, pools, virtual servers, etc.)
5. **Verify** — Check sync status, failover test

## Prerequisites

- Terraform >= 1.3.0
- Python >= 3.8
- F5 BIG-IP Terraform Provider (`F5Networks/bigip`)
- Management IP access to all BIG-IP devices
- Admin credentials

## References

- [F5 Declarative Onboarding (DO) Documentation](https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/)
- [DO Schema Reference](https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html)
- [DO GitHub Repository](https://github.com/F5Networks/f5-declarative-onboarding)
- [Terraform bigip_do Resource](https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/bigip_do)
- [K13127: Resetting BIG-IP to Factory Defaults](https://my.f5.com/manage/s/article/K13127)
