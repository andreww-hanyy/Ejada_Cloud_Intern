###############################################################################
# storage.tf - OCI File Storage: file system, mount target and export
#
# The application's files live here, not on the instance boot volume.
###############################################################################

resource "oci_file_storage_file_system" "app" {
  availability_domain = local.availability_domain
  compartment_id      = local.compartment_id
  display_name        = "${local.name_prefix}-fs"
  freeform_tags       = local.common_tags
}

# The mount target is the NFS endpoint. It lives in the private subnet and is
# protected by its own NSG, so only the application instance can reach it.
resource "oci_file_storage_mount_target" "app" {
  availability_domain = local.availability_domain
  compartment_id      = local.compartment_id
  subnet_id           = oci_core_subnet.private.id
  display_name        = "${local.name_prefix}-mt"
  nsg_ids             = [oci_core_network_security_group.fss.id]
  freeform_tags       = local.common_tags
}

# The export binds the file system to the mount target's export set at a path.
resource "oci_file_storage_export" "app" {
  export_set_id  = oci_file_storage_mount_target.app.export_set_id
  file_system_id = oci_file_storage_file_system.app.id
  path           = var.fss_export_path

  export_options {
    source                         = local.private_subnet_cidr
    access                         = "READ_WRITE"
    identity_squash                = "NONE"
    require_privileged_source_port = false
  }
}
