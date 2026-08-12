###############################################################################
# outputs.tf - what Terraform reports after apply
###############################################################################

output "application_url" {
  description = "Open this in a browser to reach the app through the load balancer."
  value       = "http://${oci_load_balancer_load_balancer.this.ip_address_details[0].ip_address}:${var.app_port}/"
}

output "load_balancer_public_ip" {
  description = "Public IP assigned to the load balancer."
  value       = oci_load_balancer_load_balancer.this.ip_address_details[0].ip_address
}

output "vcn" {
  description = "VCN name and CIDR."
  value = {
    id   = oci_core_vcn.this.id
    name = oci_core_vcn.this.display_name
    cidr = var.vcn_cidr
  }
}

output "subnets" {
  description = "Subnet CIDRs derived from the VCN CIDR."
  value = {
    public  = local.public_subnet_cidr
    private = local.private_subnet_cidr
  }
}

output "app_instance" {
  description = "The private application instance. Note there is no public IP."
  value = {
    id         = oci_core_instance.app.id
    name       = oci_core_instance.app.display_name
    private_ip = oci_core_instance.app.private_ip
    state      = oci_core_instance.app.state
    image      = data.oci_core_images.app.images[0].display_name
  }
}

output "file_storage" {
  description = "File Storage details and the exact NFS mount command used on the instance."
  value = {
    file_system_id  = oci_file_storage_file_system.app.id
    mount_target_ip = local.mount_target_ip
    export_path     = var.fss_export_path
    mount_command   = "sudo mount ${local.mount_target_ip}:${var.fss_export_path} ${var.app_document_root}"
  }
}

output "bastion_id" {
  description = "OCID of the OCI Bastion, or null when create_bastion = false."
  value       = var.create_bastion ? oci_bastion_bastion.this[0].id : null
}

output "bastion_session_command" {
  description = "OCI CLI command that opens a managed SSH session, when a bastion exists."
  value = var.create_bastion ? join(" ", [
    "oci bastion session create-managed-ssh",
    "--bastion-id ${oci_bastion_bastion.this[0].id}",
    "--target-resource-id ${oci_core_instance.app.id}",
    "--target-os-username opc",
    "--target-private-ip ${oci_core_instance.app.private_ip}",
    "--ssh-public-key-file <path-to-your-public-key>"
  ]) : "Bastion not created (create_bastion = false)."
}
