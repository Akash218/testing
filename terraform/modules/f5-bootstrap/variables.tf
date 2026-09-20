# ==============================================================================
# F5 BIG-IP Bootstrap Module — Variables
#
# DO Schema Reference:
#   https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html
# DO Clustering (HA) Examples:
#   https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/clustering.html
# Terraform bigip_do:
#   https://registry.terraform.io/providers/F5Networks/bigip/latest/docs/resources/bigip_do
# ==============================================================================

# ------------------------------------------------------------------------------
# General
# ------------------------------------------------------------------------------

variable "do_timeout" {
  description = "Timeout in minutes for the DO declaration to complete"
  type        = number
  default     = 30
}

# ------------------------------------------------------------------------------
# System — DO class: System
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#system
# ------------------------------------------------------------------------------

variable "hostname" {
  description = "FQDN hostname for the BIG-IP device (e.g., bigip-dr-active.example.com)"
  type        = string
}

variable "auto_phonehome" {
  description = "Enable or disable auto phone-home to F5"
  type        = bool
  default     = false
}

variable "console_inactivity_timeout" {
  description = "Console inactivity timeout in seconds (0 = disabled)"
  type        = number
  default     = 0
}

variable "cli_inactivity_timeout" {
  description = "CLI inactivity timeout in seconds (0 = disabled)"
  type        = number
  default     = 0
}

# ------------------------------------------------------------------------------
# License — DO class: License
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#license
# ------------------------------------------------------------------------------

variable "registration_key" {
  description = "BIG-IP registration license key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX). Leave empty to skip licensing."
  type        = string
  default     = ""
  sensitive   = true
}

variable "addon_keys" {
  description = "List of add-on license keys"
  type        = list(string)
  default     = []
  sensitive   = true
}

# ------------------------------------------------------------------------------
# Provisioning — DO class: Provision
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#provision
# Levels: nominal, minimum, dedicated, none
# ------------------------------------------------------------------------------

variable "provisioning" {
  description = "Map of module names to provisioning levels (e.g., { ltm = \"nominal\", asm = \"nominal\" })"
  type        = map(string)
  default = {
    ltm = "nominal"
  }
}

# ------------------------------------------------------------------------------
# DNS — DO class: DNS
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#dns
# ------------------------------------------------------------------------------

variable "dns_nameservers" {
  description = "List of DNS name server IPs"
  type        = list(string)
}

variable "dns_search_domains" {
  description = "List of DNS search domains"
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# NTP — DO class: NTP
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#ntp
# ------------------------------------------------------------------------------

variable "ntp_servers" {
  description = "List of NTP server addresses"
  type        = list(string)
}

variable "timezone" {
  description = "System timezone (e.g., Asia/Kolkata, UTC, America/New_York)"
  type        = string
  default     = "UTC"
}

# ------------------------------------------------------------------------------
# VLANs — DO class: VLAN
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#vlan
# ------------------------------------------------------------------------------

variable "vlans" {
  description = "List of VLAN configurations"
  type = list(object({
    name = string
    tag  = number
    mtu  = optional(number, 1500)
    interfaces = list(object({
      name   = string
      tagged = optional(bool, true)
    }))
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Self-IPs — DO class: SelfIp
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#selfip
# ------------------------------------------------------------------------------

variable "self_ips" {
  description = "List of Self-IP configurations"
  type = list(object({
    name          = string
    address       = string # CIDR format: 10.1.10.1/24
    vlan          = string # Must match a VLAN name from the vlans variable
    traffic_group = optional(string, "traffic-group-local-only")
    allow_service = optional(string, "default") # "default", "all", "none", or list like "tcp:443"
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Routes — DO class: Route
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#route
# ------------------------------------------------------------------------------

variable "routes" {
  description = "List of route configurations"
  type = list(object({
    name    = string
    network = string # CIDR format or "default" for 0.0.0.0/0
    gateway = string
    mtu     = optional(number, 1500)
  }))
  default = []
}

# ------------------------------------------------------------------------------
# SMTP — DO class: not a native DO class, included via DbVariables or external
# For initial bootstrap, SMTP is typically configured after DO via existing Terraform.
# Uncomment if you want DO to handle SMTP.
# ------------------------------------------------------------------------------

# variable "smtp" {
#   description = "SMTP configuration (optional)"
#   type = object({
#     name = string
#     host = string
#     port = optional(number, 25)
#     from = optional(string, "")
#   })
#   default = null
# }

# ------------------------------------------------------------------------------
# Syslog — DO class: SyslogRemoteServer
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#syslogremoteserver
# ------------------------------------------------------------------------------

variable "syslog_remote_servers" {
  description = "List of remote syslog server configurations"
  type = list(object({
    name = string
    host = string
    port = optional(number, 514)
  }))
  default = []
}

# ------------------------------------------------------------------------------
# SNMP — DO class: SnmpAgent
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#snmpagent
# ------------------------------------------------------------------------------

variable "snmp_agent" {
  description = "SNMP agent configuration (optional)"
  type = object({
    contact    = optional(string, "")
    location   = optional(string, "")
    allow_list = optional(list(string), [])
  })
  default = null
}

variable "snmp_trap_destinations" {
  description = "List of SNMP trap destination configurations"
  type = list(object({
    name        = string
    destination = string
    port        = optional(number, 162)
    version     = optional(string, "2c")
    community   = optional(string, "public")
    network     = optional(string, "other")
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Users — DO class: User
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#user
# ------------------------------------------------------------------------------

variable "users" {
  description = "List of local user accounts to create"
  type = list(object({
    name      = string
    password  = string
    role      = optional(string, "admin")
    shell     = optional(string, "tmsh")
    partition = optional(string, "all-partitions")
    user_type = optional(string, "regular")
  }))
  default   = []
  sensitive = true
}

# ------------------------------------------------------------------------------
# HA — ConfigSync — DO class: ConfigSync
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#configsync
# Set on BOTH Active and Standby devices.
# ------------------------------------------------------------------------------

variable "configsync_ip" {
  description = "Self-IP address (or reference like /Common/ha-self/address) used for config sync. Set on BOTH devices."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# HA — Failover Unicast — DO class: FailoverUnicast
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#failoverunicast
# Set on BOTH Active and Standby devices.
# ------------------------------------------------------------------------------

variable "failover_unicast_address" {
  description = "Self-IP address used for failover heartbeat. Set on BOTH devices."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# HA — Mirror — DO class: MirrorIp
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#mirrorip
# Set on BOTH Active and Standby devices.
# ------------------------------------------------------------------------------

variable "mirror_primary_ip" {
  description = "Primary mirror IP (typically HA Self-IP). Set on BOTH devices."
  type        = string
  default     = ""
}

variable "mirror_secondary_ip" {
  description = "Secondary mirror IP (typically Internal Self-IP). Set on BOTH devices."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# HA — Device Trust — DO class: DeviceTrust
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#devicetrust
# Set ONLY on the ACTIVE device. DO will reach out to the Standby to establish trust.
# ------------------------------------------------------------------------------

variable "device_trust" {
  description = "Device trust configuration. Set ONLY on the ACTIVE device. Set to null for Standby."
  type = object({
    remote_host     = string # Management IP of the peer (Standby) device
    remote_username = string
    remote_password = string
    local_username  = string
    local_password  = string
  })
  default   = null
  sensitive = true
}

# ------------------------------------------------------------------------------
# HA — Device Group — DO class: DeviceGroup
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#devicegroup
# Set ONLY on the ACTIVE device.
# ------------------------------------------------------------------------------

variable "device_group" {
  description = "Device group (sync-failover) configuration. Set ONLY on the ACTIVE device."
  type = object({
    name              = string
    members           = list(string) # List of device hostnames (FQDNs)
    owner             = string       # Hostname of the device that owns the config (Active device)
    auto_sync         = optional(bool, true)
    save_on_auto_sync = optional(bool, false)
    network_failover  = optional(bool, true)
    full_load_on_sync = optional(bool, false)
  })
  default = null
}

# ------------------------------------------------------------------------------
# HA — Traffic Group — DO class: TrafficGroup
# https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html#trafficgroup
# Optional: configure custom traffic groups.
# ------------------------------------------------------------------------------

variable "traffic_groups" {
  description = "List of traffic group configurations (optional)"
  type = list(object({
    name                       = string
    auto_failback_enabled      = optional(bool, false)
    auto_failback_idle_seconds = optional(number, 60)
    failover_method            = optional(string, "ha-order")
    ha_load_factor             = optional(number, 1)
  }))
  default = []
}
