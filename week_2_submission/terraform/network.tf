###############################################################################
# network.tf - VCN, gateways, route tables, security lists and subnets
###############################################################################

resource "oci_core_vcn" "this" {
  compartment_id = local.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${local.name_prefix}-vcn"
  dns_label      = local.vcn_dns_label
  freeform_tags  = local.common_tags
}

# ----------------------------------------------------------------------------
# Gateways
# ----------------------------------------------------------------------------

# Public subnet -> internet (inbound and outbound).
resource "oci_core_internet_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

# Private subnet -> internet (outbound only). Needed so the instance can
# install packages without ever being reachable from the internet.
resource "oci_core_nat_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-natgw"
  freeform_tags  = local.common_tags
}

# Private subnet -> OCI services (Object Storage, etc.) over the Oracle
# backbone instead of the NAT gateway.
resource "oci_core_service_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-sgw"
  freeform_tags  = local.common_tags

  services {
    service_id = data.oci_core_services.oracle_services_network.services[0]["id"]
  }
}

# ----------------------------------------------------------------------------
# Route tables
# ----------------------------------------------------------------------------

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-rt-public"
  freeform_tags  = local.common_tags

  route_rules {
    description       = "Default route to the internet gateway"
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-rt-private"
  freeform_tags  = local.common_tags

  route_rules {
    description       = "Outbound internet access via the NAT gateway"
    destination       = local.anywhere
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    description       = "OCI service traffic via the service gateway"
    destination       = data.oci_core_services.oracle_services_network.services[0]["cidr_block"]
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

# ----------------------------------------------------------------------------
# Security lists
#
# These stay deliberately thin: they only carry egress and ICMP path-MTU.
# All application-level rules live in NSGs (see security.tf), which are
# attached directly to the load balancer, the instance and the mount target.
# OCI evaluates security lists and NSGs as a union, so this is additive.
# ----------------------------------------------------------------------------

resource "oci_core_security_list" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-sl-public"
  freeform_tags  = local.common_tags

  egress_security_rules {
    description      = "Allow all outbound"
    destination      = local.anywhere
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    description = "Path MTU discovery"
    source      = local.anywhere
    source_type = "CIDR_BLOCK"
    protocol    = "1" # ICMP

    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${local.name_prefix}-sl-private"
  freeform_tags  = local.common_tags

  egress_security_rules {
    description      = "Allow all outbound"
    destination      = local.anywhere
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    description = "Path MTU discovery from inside the VCN"
    source      = var.vcn_cidr
    source_type = "CIDR_BLOCK"
    protocol    = "1" # ICMP

    icmp_options {
      type = 3
      code = 4
    }
  }
}

# ----------------------------------------------------------------------------
# Subnets
# ----------------------------------------------------------------------------

resource "oci_core_subnet" "public" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.public_subnet_cidr
  display_name               = "${local.name_prefix}-subnet-public"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = local.common_tags
}

resource "oci_core_subnet" "private" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.private_subnet_cidr
  display_name               = "${local.name_prefix}-subnet-private"
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.common_tags
}
