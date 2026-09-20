# ==============================================================================
# DC Environment — Variables
# ==============================================================================

# ------------------------------------------------------------------------------
# Provider / Connection
# ------------------------------------------------------------------------------

variable "active_bigip_address" {
  description = "Management IP or hostname of the DR ACTIVE BIG-IP device"
  type        = string
}

variable "standby_bigip_address" {
  description = "Management IP or hostname of the DR STANDBY BIG-IP device"
  type        = string
}

variable "bigip_username" {
  description = "Admin username for BIG-IP devices"
  type        = string
  default     = "admin"
}

variable "bigip_password" {
  description = "Admin password for BIG-IP devices"
  type        = string
  sensitive   = true
}

variable "bigip_port" {
  description = "Management port for BIG-IP devices"
  type        = string
  default     = "443"
}

# ------------------------------------------------------------------------------
# Shared settings (applied to BOTH Active and Standby)
# ------------------------------------------------------------------------------

variable "dns_nameservers" {
  description = "DNS name servers"
  type        = list(string)
}

variable "dns_search_domains" {
  description = "DNS search domains"
  type        = list(string)
  default     = []
}

variable "ntp_servers" {
  description = "NTP servers"
  type        = list(string)
}

variable "timezone" {
  description = "System timezone"
  type        = string
  default     = "UTC"
}

variable "provisioning" {
  description = "Module provisioning levels"
  type        = map(string)
  default     = { ltm = "nominal" }
}

# ------------------------------------------------------------------------------
# Active device specifics
# ------------------------------------------------------------------------------

variable "active_hostname" {
  description = "FQDN hostname for the DR Active device"
  type        = string
}

variable "active_registration_key" {
  description = "License registration key for the DR Active device"
  type        = string
  sensitive   = true
}

variable "active_vlans" {
  description = "VLAN configurations for the DR Active device"
  type = list(object({
    name = string
    tag  = number
    mtu  = optional(number, 1500)
    interfaces = list(object({
      name   = string
      tagged = optional(bool, true)
    }))
  }))
}

variable "active_self_ips" {
  description = "Self-IP configurations for the DR Active device"
  type = list(object({
    name          = string
    address       = string
    vlan          = string
    traffic_group = optional(string, "traffic-group-local-only")
    allow_service = optional(string, "default")
  }))
}

variable "active_routes" {
  description = "Route configurations for the DR Active device"
  type = list(object({
    name    = string
    network = string
    gateway = string
    mtu     = optional(number, 1500)
  }))
  default = []
}

variable "active_configsync_ip" {
  description = "ConfigSync IP for the DR Active device"
  type        = string
}

variable "active_failover_unicast_address" {
  description = "Failover unicast address for the DR Active device"
  type        = string
}

variable "active_mirror_primary_ip" {
  description = "Primary mirror IP for the DR Active device"
  type        = string
  default     = ""
}

variable "active_mirror_secondary_ip" {
  description = "Secondary mirror IP for the DR Active device"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Standby device specifics
# ------------------------------------------------------------------------------

variable "standby_hostname" {
  description = "FQDN hostname for the DR Standby device"
  type        = string
}

variable "standby_registration_key" {
  description = "License registration key for the DR Standby device"
  type        = string
  sensitive   = true
}

variable "standby_vlans" {
  description = "VLAN configurations for the DR Standby device"
  type = list(object({
    name = string
    tag  = number
    mtu  = optional(number, 1500)
    interfaces = list(object({
      name   = string
      tagged = optional(bool, true)
    }))
  }))
}

variable "standby_self_ips" {
  description = "Self-IP configurations for the DR Standby device"
  type = list(object({
    name          = string
    address       = string
    vlan          = string
    traffic_group = optional(string, "traffic-group-local-only")
    allow_service = optional(string, "default")
  }))
}

variable "standby_routes" {
  description = "Route configurations for the DR Standby device"
  type = list(object({
    name    = string
    network = string
    gateway = string
    mtu     = optional(number, 1500)
  }))
  default = []
}

variable "standby_configsync_ip" {
  description = "ConfigSync IP for the DR Standby device"
  type        = string
}

variable "standby_failover_unicast_address" {
  description = "Failover unicast address for the DR Standby device"
  type        = string
}

variable "standby_mirror_primary_ip" {
  description = "Primary mirror IP for the DR Standby device"
  type        = string
  default     = ""
}

variable "standby_mirror_secondary_ip" {
  description = "Secondary mirror IP for the DR Standby device"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# HA / Device Group
# ------------------------------------------------------------------------------

variable "device_group_name" {
  description = "Name of the sync-failover device group"
  type        = string
}

variable "users" {
  description = "Local user accounts to create on both devices"
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

variable "syslog_remote_servers" {
  description = "Remote syslog server configurations"
  type = list(object({
    name = string
    host = string
    port = optional(number, 514)
  }))
  default = []
}

variable "snmp_agent" {
  description = "SNMP agent configuration"
  type = object({
    contact    = optional(string, "")
    location   = optional(string, "")
    allow_list = optional(list(string), [])
  })
  default = null
}

variable "snmp_trap_destinations" {
  description = "SNMP trap destination configurations"
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
