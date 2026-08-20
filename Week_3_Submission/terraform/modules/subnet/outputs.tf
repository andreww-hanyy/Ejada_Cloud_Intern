output "subnet_id" {
  description = "OCID of the subnet."
  value       = oci_core_subnet.this.id
}

output "subnet_name" {
  description = "Display name of the subnet."
  value       = oci_core_subnet.this.display_name
}

output "cidr_block" {
  description = "CIDR block of the subnet, echoed back so callers can build security rules from module outputs instead of repeating literals."
  value       = oci_core_subnet.this.cidr_block
}

output "is_public" {
  description = "Whether the subnet permits public IPs and internet ingress."
  value       = var.is_public
}

output "route_table_id" {
  description = "OCID of the route table attached to the subnet (created by this module, or the one passed in)."
  value       = local.attached_route_table_id
}

output "security_list_ids" {
  description = "All security list OCIDs attached to the subnet."
  value       = local.attached_security_list_ids
}

output "security_list_id" {
  description = "OCID of the security list this module created, or null when create_security_list = false."
  value       = try(oci_core_security_list.this[0].id, null)
}

output "flow_log_id" {
  description = "OCID of the flow log, or null when flow logs are disabled."
  value       = try(oci_logging_log.flow[0].id, null)
}

output "flow_log_group_id" {
  description = "OCID of the log group holding the flow log, or null when flow logs are disabled."
  value       = local.flow_log_group_id
}
