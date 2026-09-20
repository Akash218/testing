# ==============================================================================
# F5 BIG-IP Bootstrap Module — Main
#
# Builds a Declarative Onboarding (DO) JSON declaration from variables and
# applies it to the BIG-IP device using the bigip_do resource.
#
# DO Documentation:
#   https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/
# DO Schema Reference:
#   https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/schema-reference.html
# DO Clustering (HA) Examples:
#   https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/clustering.html
# ==============================================================================

locals {

  # ────────────────────────────────────────────────────────────────────────────
  # System
  # ────────────────────────────────────────────────────────────────────────────
  system_config = {
    mySystem = {
      class                    = "System"
      hostname                 = var.hostname
      consoleInactivityTimeout = var.console_inactivity_timeout
      cliInactivityTimeout     = var.cli_inactivity_timeout
      autoPhonehome            = var.auto_phonehome
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # License (conditional — skip if registration_key is empty)
  # ────────────────────────────────────────────────────────────────────────────
  license_config = var.registration_key != "" ? {
    myLicense = {
      class       = "License"
      licenseType = "regKey"
      regKey      = var.registration_key
      addOnKeys   = length(var.addon_keys) > 0 ? var.addon_keys : null
      overwrite   = false
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # Provisioning
  # ────────────────────────────────────────────────────────────────────────────
  provision_config = {
    myProvisioning = merge(
      { class = "Provision" },
      var.provisioning
    )
  }

  # ────────────────────────────────────────────────────────────────────────────
  # DNS
  # ────────────────────────────────────────────────────────────────────────────
  dns_config = {
    myDns = {
      class       = "DNS"
      nameServers = var.dns_nameservers
      search      = var.dns_search_domains
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # NTP
  # ────────────────────────────────────────────────────────────────────────────
  ntp_config = {
    myNtp = {
      class    = "NTP"
      servers  = var.ntp_servers
      timezone = var.timezone
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # VLANs
  # ────────────────────────────────────────────────────────────────────────────
  vlan_configs = { for vlan in var.vlans :
    vlan.name => {
      class = "VLAN"
      tag   = vlan.tag
      mtu   = vlan.mtu
      interfaces = [for iface in vlan.interfaces : {
        name   = iface.name
        tagged = iface.tagged
      }]
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Self-IPs
  # ────────────────────────────────────────────────────────────────────────────
  self_ip_configs = { for self_ip in var.self_ips :
    self_ip.name => {
      class        = "SelfIp"
      address      = self_ip.address
      vlan         = self_ip.vlan
      trafficGroup = self_ip.traffic_group
      allowService = self_ip.allow_service
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Routes
  # ────────────────────────────────────────────────────────────────────────────
  route_configs = { for route in var.routes :
    route.name => {
      class   = "Route"
      gw      = route.gateway
      network = route.network
      mtu     = route.mtu
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Users
  # ────────────────────────────────────────────────────────────────────────────
  user_configs = { for user in var.users :
    user.name => {
      class    = "User"
      userType = user.user_type
      password = user.password
      shell    = user.shell
      partitionAccess = {
        (user.partition) = {
          role = user.role
        }
      }
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Syslog Remote Servers
  # ────────────────────────────────────────────────────────────────────────────
  syslog_configs = { for server in var.syslog_remote_servers :
    server.name => {
      class      = "SyslogRemoteServer"
      host       = server.host
      remotePort = server.port
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # SNMP Agent
  # ────────────────────────────────────────────────────────────────────────────
  snmp_agent_config = var.snmp_agent != null ? {
    mySnmpAgent = {
      class     = "SnmpAgent"
      contact   = var.snmp_agent.contact
      location  = var.snmp_agent.location
      allowList = var.snmp_agent.allow_list
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # SNMP Trap Destinations
  # ────────────────────────────────────────────────────────────────────────────
  snmp_trap_configs = { for trap in var.snmp_trap_destinations :
    trap.name => {
      class       = "SnmpTrapDestination"
      version     = trap.version
      community   = trap.community
      destination = trap.destination
      port        = trap.port
      network     = trap.network
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Traffic Groups
  # ────────────────────────────────────────────────────────────────────────────
  traffic_group_configs = { for tg in var.traffic_groups :
    tg.name => {
      class                      = "TrafficGroup"
      autoFailbackEnabled        = tg.auto_failback_enabled
      autoFailbackIdleSeconds    = tg.auto_failback_idle_seconds
      failoverMethod             = tg.failover_method
      haLoadFactor               = tg.ha_load_factor
    }
  }

  # ────────────────────────────────────────────────────────────────────────────
  # HA — ConfigSync (set on BOTH devices)
  # ────────────────────────────────────────────────────────────────────────────
  configsync_config = var.configsync_ip != "" ? {
    configsync = {
      class        = "ConfigSync"
      configsyncIp = var.configsync_ip
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # HA — Failover Unicast (set on BOTH devices)
  # ────────────────────────────────────────────────────────────────────────────
  failover_config = var.failover_unicast_address != "" ? {
    failoverAddress = {
      class   = "FailoverUnicast"
      address = var.failover_unicast_address
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # HA — Mirror (set on BOTH devices)
  # ────────────────────────────────────────────────────────────────────────────
  mirror_config = var.mirror_primary_ip != "" ? {
    myMirror = {
      class       = "MirrorIp"
      primaryIp   = var.mirror_primary_ip
      secondaryIp = var.mirror_secondary_ip
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # HA — Device Trust (set ONLY on ACTIVE device)
  # ────────────────────────────────────────────────────────────────────────────
  device_trust_config = var.device_trust != null ? {
    myDeviceTrust = {
      class          = "DeviceTrust"
      localUsername   = var.device_trust.local_username
      localPassword   = var.device_trust.local_password
      remoteHost     = var.device_trust.remote_host
      remoteUsername  = var.device_trust.remote_username
      remotePassword  = var.device_trust.remote_password
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # HA — Device Group (set ONLY on ACTIVE device)
  # ────────────────────────────────────────────────────────────────────────────
  device_group_config = var.device_group != null ? {
    (var.device_group.name) = {
      class           = "DeviceGroup"
      type            = "sync-failover"
      members         = var.device_group.members
      owner           = "/Common/${var.device_group.name}/members/0"
      autoSync        = var.device_group.auto_sync
      saveOnAutoSync  = var.device_group.save_on_auto_sync
      networkFailover = var.device_group.network_failover
      fullLoadOnSync  = var.device_group.full_load_on_sync
    }
  } : {}

  # ────────────────────────────────────────────────────────────────────────────
  # Assemble the complete DO declaration
  # ────────────────────────────────────────────────────────────────────────────
  tenant_common = merge(
    { class = "Tenant" },
    local.system_config,
    local.license_config,
    local.provision_config,
    local.dns_config,
    local.ntp_config,
    local.vlan_configs,
    local.self_ip_configs,
    local.route_configs,
    local.user_configs,
    local.syslog_configs,
    local.snmp_agent_config,
    local.snmp_trap_configs,
    local.traffic_group_configs,
    local.configsync_config,
    local.failover_config,
    local.mirror_config,
    local.device_trust_config,
    local.device_group_config,
  )

  do_declaration = {
    schemaVersion = "1.0.0"
    class         = "Device"
    async         = true
    label         = "Bootstrap ${var.hostname}"
    Common        = local.tenant_common
  }
}

# ==============================================================================
# Apply the DO declaration to the BIG-IP device
# ==============================================================================

resource "bigip_do" "this" {
  do_json = jsonencode(local.do_declaration)
  timeout = var.do_timeout
}
