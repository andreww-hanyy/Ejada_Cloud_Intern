###############################################################################
# data.tf - everything Terraform looks up instead of being told
###############################################################################

# Availability domains available to this compartment.
data "oci_identity_availability_domains" "this" {
  compartment_id = local.compartment_id
}

# Latest platform image matching the requested OS, version and shape.
data "oci_core_images" "app" {
  compartment_id           = local.compartment_id
  operating_system         = var.instance_os
  operating_system_version = var.instance_os_version
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# The "All <region> Services In Oracle Services Network" service CIDR,
# used by the service gateway and its route rule.
data "oci_core_services" "oracle_services_network" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# The mount target exposes private IP OCIDs; this resolves one to an IP address.
data "oci_core_private_ip" "mount_target" {
  private_ip_id = oci_file_storage_mount_target.app.private_ip_ids[0]
}
