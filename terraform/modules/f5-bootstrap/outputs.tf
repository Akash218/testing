output "do_declaration_json" {
  description = "The rendered DO JSON declaration (for debugging). Sensitive fields are redacted."
  value       = bigip_do.this.do_json
  sensitive   = true
}

output "do_id" {
  description = "The ID of the bigip_do resource"
  value       = bigip_do.this.id
}

output "hostname" {
  description = "The hostname configured on this device"
  value       = var.hostname
}
