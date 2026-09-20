output "dc_active_hostname" {
  description = "Hostname of the DC Active device"
  value       = module.dc_active_bootstrap.hostname
}

output "dc_standby_hostname" {
  description = "Hostname of the DC Standby device"
  value       = module.dc_standby_bootstrap.hostname
}

output "dc_active_do_id" {
  description = "DO resource ID for the DC Active device"
  value       = module.dc_active_bootstrap.do_id
}

output "dc_standby_do_id" {
  description = "DO resource ID for the DC Standby device"
  value       = module.dc_standby_bootstrap.do_id
}
