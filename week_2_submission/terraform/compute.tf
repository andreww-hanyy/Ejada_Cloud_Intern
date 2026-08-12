###############################################################################
# compute.tf - the private application instance
###############################################################################

resource "oci_core_instance" "app" {
  compartment_id      = local.compartment_id
  availability_domain = local.availability_domain
  display_name        = "${local.name_prefix}-app"
  shape               = var.instance_shape
  freeform_tags       = local.common_tags

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.app.images[0].id
  }

  # No public IP. The only ways in are the load balancer (port 80, from the
  # LB NSG only) and an OCI Bastion managed-SSH session.
  create_vnic_details {
    subnet_id                 = oci_core_subnet.private.id
    assign_public_ip          = false
    hostname_label            = "app"
    nsg_ids                   = [oci_core_network_security_group.app.id]
    assign_private_dns_record = true
  }

  # Oracle Cloud Agent must expose the Bastion plugin for managed SSH sessions.
  agent_config {
    is_management_disabled = false
    is_monitoring_disabled = false

    plugins_config {
      name          = "Bastion"
      desired_state = "ENABLED"
    }
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key

    user_data = base64encode(templatefile("${path.module}/cloud-init.sh.tftpl", {
      app_document_root = var.app_document_root
      mount_target_ip   = local.mount_target_ip
      export_path       = var.fss_export_path
      app_port          = var.app_port
      app_title         = "${var.project_name} - ${var.environment}"
    }))
  }

  # The export must exist before the instance tries to mount it.
  depends_on = [oci_file_storage_export.app]

  lifecycle {
    # Changing the image would destroy and rebuild the instance. Remove this
    # line deliberately when you actually want to re-image.
    ignore_changes = [source_details[0].source_id]
  }
}
