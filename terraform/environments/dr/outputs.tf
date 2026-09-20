# ==============================================================================
# DR Environment — Outputs
# ==============================================================================

output "dr_active_hostname" {
  description = "Hostname of the DR Active device"
  value       = module.dr_active_bootstrap.hostname
}

output "dr_standby_hostname" {
  description = "Hostname of the DR Standby device"
  value       = module.dr_standby_bootstrap.hostname
}

output "dr_active_do_id" {
  description = "DO resource ID for the DR Active device"
  value       = module.dr_active_bootstrap.do_id
}

output "dr_standby_do_id" {
  description = "DO resource ID for the DR Standby device"
  value       = module.dr_standby_bootstrap.do_id
}
