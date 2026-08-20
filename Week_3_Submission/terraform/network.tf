###############################################################################
# VCN and gateways
#
# These are VCN-scoped, shared by every subnet, so they live in the root and
# not in the subnet module. The module's job is one subnet and its three
# companions -- not the whole network.
###############################################################################

data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.prefix}-vcn"
  dns_label      = replace(replace(var.prefix, "-", ""), "_", "")

  freeform_tags = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.prefix}-igw"
  enabled        = true

  freeform_tags = var.freeform_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.prefix}-natgw"

  freeform_tags = var.freeform_tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.prefix}-sgw"

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }

  freeform_tags = var.freeform_tags
}

# OCI auto-creates a default security list with SSH open to 0.0.0.0/0 whenever a
# VCN is created. None of the four subnets attach it -- they all get their own
# from the module -- but leaving a permissive object lying around in the
# compartment is untidy and fails CIS checks. Adopting it with no rules at all
# closes it without a manual Console step.
resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "${var.prefix}-default-sl-empty"

  # No ingress_security_rules and no egress_security_rules blocks: deny all.

  freeform_tags = var.freeform_tags
}

# One log group shared by all four subnets. Passing this into the module means
# the module skips creating its own -- the conditional inside modules/subnet.
resource "oci_logging_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.prefix}-flow-logs"
  description    = "VCN flow logs for every subnet in ${var.prefix}-vcn."

  freeform_tags = var.freeform_tags
}
