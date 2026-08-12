###############################################################################
# bastion.tf - OCI Bastion service for administrative access
#
# The bastion is a managed service, not a VM. It creates a private endpoint in
# the target subnet and brokers SSH sessions to instances running the Oracle
# Cloud Agent Bastion plugin.
###############################################################################

# NOTE ON PERMISSIONS
# The OCI Bastion service is a separate IAM resource family (bastion-family).
# The account used for this lab holds `read` but not `manage` on it, so
# `oci bastion bastion create` returns NotAuthorizedOrNotFound. Creation is
# therefore gated behind a variable and disabled by default, so that
# `terraform apply` succeeds without the grant. Set create_bastion = true
# once the policy below is in place:
#
#   allow group <interns> to manage bastion-family in compartment <name>
#
# See Section 9, Issue 4 of the technical report.

resource "oci_bastion_bastion" "this" {
  count = var.create_bastion ? 1 : 0

  bastion_type                 = "standard"
  compartment_id               = local.compartment_id
  target_subnet_id             = oci_core_subnet.private.id
  name                         = replace("${local.name_prefix}-bastion", "-", "_")
  client_cidr_block_allow_list = var.bastion_client_cidr_allow_list
  max_session_ttl_in_seconds   = var.bastion_max_session_ttl_seconds
  freeform_tags                = local.common_tags
}

# Optional. Bastion sessions expire, which makes `terraform plan` show drift,
# so this is off by default - create sessions from the Console or OCI CLI.
# Enable with: create_bastion_session = true
resource "oci_bastion_session" "managed_ssh" {
  count = var.create_bastion && var.create_bastion_session ? 1 : 0

  bastion_id             = oci_bastion_bastion.this[0].id
  display_name           = "${local.name_prefix}-session"
  session_ttl_in_seconds = var.bastion_max_session_ttl_seconds

  key_details {
    public_key_content = var.ssh_public_key
  }

  target_resource_details {
    session_type                               = "MANAGED_SSH"
    target_resource_id                         = oci_core_instance.app.id
    target_resource_operating_system_user_name = "opc"
    target_resource_port                       = 22
    target_resource_private_ip_address         = oci_core_instance.app.private_ip
  }
}
