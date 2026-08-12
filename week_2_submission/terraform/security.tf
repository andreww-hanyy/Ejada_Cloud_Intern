###############################################################################
# security.tf - Network Security Groups
#
# Three NSGs, each attached to exactly one tier. Rules reference the *other
# NSG* rather than a CIDR, so the intent reads as "only the load balancer may
# talk to the app" instead of "anything in 10.0.1.0/24 may talk to the app".
###############################################################################

resource "oci_core_network_security_group" "lb" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-nsg-lb"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group" "app" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-nsg-app"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group" "fss" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-nsg-fss"
  freeform_tags  = local.common_tags
}

# ----------------------------------------------------------------------------
# Load balancer: open to clients on the app port, free to reach the backend
# ----------------------------------------------------------------------------

resource "oci_core_network_security_group_security_rule" "lb_ingress_http" {
  network_security_group_id = oci_core_network_security_group.lb.id
  description               = "Client traffic to the load balancer listener"
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.allowed_http_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = var.app_port
      max = var.app_port
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_egress_app" {
  network_security_group_id = oci_core_network_security_group.lb.id
  description               = "Forward traffic and health checks to the app NSG"
  direction                 = "EGRESS"
  protocol                  = "6" # TCP
  destination               = oci_core_network_security_group.app.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = var.app_port
      max = var.app_port
    }
  }
}

# ----------------------------------------------------------------------------
# Application instance
# ----------------------------------------------------------------------------

resource "oci_core_network_security_group_security_rule" "app_ingress_from_lb" {
  network_security_group_id = oci_core_network_security_group.app.id
  description               = "Only the load balancer may reach the application port"
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = var.app_port
      max = var.app_port
    }
  }
}

# The OCI Bastion service reaches the instance from a private endpoint it
# creates inside this VCN, so SSH is allowed from the VCN CIDR only.
resource "oci_core_network_security_group_security_rule" "app_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.app.id
  description               = "SSH from the OCI Bastion private endpoint inside the VCN"
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "app_egress_all" {
  network_security_group_id = oci_core_network_security_group.app.id
  description               = "Outbound for package installs (via NAT) and NFS"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = local.anywhere
  destination_type          = "CIDR_BLOCK"
}

# ----------------------------------------------------------------------------
# File Storage mount target - NFS v3 ports, app tier only
# ----------------------------------------------------------------------------

resource "oci_core_network_security_group_security_rule" "fss_ingress_tcp" {
  for_each = toset([for p in local.nfs_tcp_ports : tostring(p)])

  network_security_group_id = oci_core_network_security_group.fss.id
  description               = "NFS TCP ${each.value} from the application instance"
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.app.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "fss_ingress_udp" {
  for_each = toset([for p in local.nfs_udp_ports : tostring(p)])

  network_security_group_id = oci_core_network_security_group.fss.id
  description               = "NFS UDP ${each.value} from the application instance"
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = oci_core_network_security_group.app.id
  source_type               = "NETWORK_SECURITY_GROUP"

  udp_options {
    destination_port_range {
      min = tonumber(each.value)
      max = tonumber(each.value)
    }
  }
}

# NSG rules are stateful by default, so replies to the ingress rules above are
# allowed automatically. This egress rule only covers traffic the mount target
# initiates itself.
resource "oci_core_network_security_group_security_rule" "fss_egress_app" {
  network_security_group_id = oci_core_network_security_group.fss.id
  description               = "Mount target to application instance"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = oci_core_network_security_group.app.id
  destination_type          = "NETWORK_SECURITY_GROUP"
}
