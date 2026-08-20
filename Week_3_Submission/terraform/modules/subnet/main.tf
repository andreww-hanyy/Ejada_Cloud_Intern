###############################################################################
# modules/subnet
#
# One subnet and the three things that always travel with it:
#   1. oci_core_subnet
#   2. oci_core_route_table      (optional -- create_route_table)
#   3. oci_core_security_list    (optional -- create_security_list)
#   4. oci_logging_log           (optional -- flow_logs_enabled)  [+ log group]
#
# Techniques on show here:
#   * dynamic blocks           -- route rules, ingress/egress rules and their
#                                 nested tcp/udp/icmp option blocks
#   * count as a conditional   -- every optional resource is count = cond ? 1 : 0
#   * conditional expressions  -- is_public drives two subnet attributes
#   * coalesce / try / compact -- resolving "caller-supplied or module-created"
###############################################################################

locals {
  # is_public is the single knob; both subnet attributes derive from it.
  prohibit_public_ip     = !var.is_public
  prohibit_internet_ingr = !var.is_public

  # Security lists attached to the subnet = the one we made (if any) + any the
  # caller handed us. The [*] splat on a counted resource yields [] when the
  # count is 0, so no try()/compact() is needed -- and, unlike compact(), it
  # keeps the list *length* known at plan time, so the plan shows the real
  # value instead of "(known after apply)".
  attached_security_list_ids = var.create_security_list ? concat(
    oci_core_security_list.this[*].id,
    var.security_list_ids,
  ) : var.security_list_ids

  # Route table attached to the subnet: ours if we made one, otherwise the
  # caller's, otherwise null (= VCN default route table).
  attached_route_table_id = var.create_route_table ? try(oci_core_route_table.this[0].id, null) : var.route_table_id

  # Log group: the one we made, or the caller's. Deliberately the same shape as
  # attached_route_table_id above -- driven by the create_* flag, not by
  # inspecting the OCID, which may not be known until apply.
  flow_log_group_id = var.flow_logs_enabled ? (
    var.create_flow_logs_log_group
    ? try(oci_logging_log_group.this[0].id, null)
    : var.flow_logs_log_group_id
  ) : null

  common_tags = merge(var.freeform_tags, { "tf-module" = "subnet" })

  # An empty map is not the same as "unset". `defined_tags = {}` tells OCI to
  # remove every defined tag -- which fights the tenancy's Oracle-Tags default
  # namespace, where CreatedBy and CreatedOn are applied automatically at
  # creation, and leaves a permanent diff on every resource the module makes.
  # defined_tags is Optional+Computed in the provider schema, so null means
  # "leave it to the provider" and the caller's tags still win when supplied.
  defined_tags = length(var.defined_tags) > 0 ? var.defined_tags : null
}

# ---------------------------------------------------------------------------
# 1. Route table
# ---------------------------------------------------------------------------

resource "oci_core_route_table" "this" {
  count = var.create_route_table ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name}-rt"

  # One route_rules block per element of var.route_rules.
  dynamic "route_rules" {
    for_each = var.route_rules
    content {
      destination       = route_rules.value.destination
      destination_type  = route_rules.value.destination_type
      network_entity_id = route_rules.value.network_entity_id
      description       = route_rules.value.description
    }
  }

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags
}

# ---------------------------------------------------------------------------
# 2. Security list
# ---------------------------------------------------------------------------

resource "oci_core_security_list" "this" {
  count = var.create_security_list ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name}-sl"

  dynamic "ingress_security_rules" {
    for_each = var.ingress_rules
    content {
      protocol    = ingress_security_rules.value.protocol
      source      = ingress_security_rules.value.source
      source_type = ingress_security_rules.value.source_type
      stateless   = ingress_security_rules.value.stateless
      description = ingress_security_rules.value.description

      # Nested dynamic: the block exists only when the caller set the object.
      # for_each over a list of 0 or 1 elements is the idiomatic way to make
      # a *single* nested block conditional.
      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.tcp_options == null ? [] : [ingress_security_rules.value.tcp_options]
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max

          dynamic "source_port_range" {
            for_each = tcp_options.value.source_port_range == null ? [] : [tcp_options.value.source_port_range]
            content {
              min = source_port_range.value.min
              max = source_port_range.value.max
            }
          }
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.udp_options == null ? [] : [ingress_security_rules.value.udp_options]
        content {
          min = udp_options.value.min
          max = udp_options.value.max

          dynamic "source_port_range" {
            for_each = udp_options.value.source_port_range == null ? [] : [udp_options.value.source_port_range]
            content {
              min = source_port_range.value.min
              max = source_port_range.value.max
            }
          }
        }
      }

      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.icmp_options == null ? [] : [ingress_security_rules.value.icmp_options]
        content {
          type = icmp_options.value.type
          code = icmp_options.value.code
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = var.egress_rules
    content {
      protocol         = egress_security_rules.value.protocol
      destination      = egress_security_rules.value.destination
      destination_type = egress_security_rules.value.destination_type
      stateless        = egress_security_rules.value.stateless
      description      = egress_security_rules.value.description

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.tcp_options == null ? [] : [egress_security_rules.value.tcp_options]
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max

          dynamic "source_port_range" {
            for_each = tcp_options.value.source_port_range == null ? [] : [tcp_options.value.source_port_range]
            content {
              min = source_port_range.value.min
              max = source_port_range.value.max
            }
          }
        }
      }

      dynamic "udp_options" {
        for_each = egress_security_rules.value.udp_options == null ? [] : [egress_security_rules.value.udp_options]
        content {
          min = udp_options.value.min
          max = udp_options.value.max

          dynamic "source_port_range" {
            for_each = udp_options.value.source_port_range == null ? [] : [udp_options.value.source_port_range]
            content {
              min = source_port_range.value.min
              max = source_port_range.value.max
            }
          }
        }
      }

      dynamic "icmp_options" {
        for_each = egress_security_rules.value.icmp_options == null ? [] : [egress_security_rules.value.icmp_options]
        content {
          type = icmp_options.value.type
          code = icmp_options.value.code
        }
      }
    }
  }

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags
}

# ---------------------------------------------------------------------------
# 3. Subnet
# ---------------------------------------------------------------------------

resource "oci_core_subnet" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  cidr_block     = var.cidr_block
  display_name   = var.name
  dns_label      = var.dns_label

  # null => regional subnet (required by OKE); set => AD-specific subnet.
  availability_domain = var.availability_domain

  route_table_id    = local.attached_route_table_id
  security_list_ids = length(local.attached_security_list_ids) > 0 ? local.attached_security_list_ids : null
  dhcp_options_id   = var.dhcp_options_id

  prohibit_public_ip_on_vnic = local.prohibit_public_ip
  prohibit_internet_ingress  = local.prohibit_internet_ingr

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags

  lifecycle {
    precondition {
      condition     = var.create_security_list || length(var.security_list_ids) > 0
      error_message = "With create_security_list = false you must pass at least one existing OCID in security_list_ids."
    }
  }
}

# ---------------------------------------------------------------------------
# 4. Flow logs
# ---------------------------------------------------------------------------

# Only created when the caller enabled flow logs AND asked for its own group.
#
# The flag, not `var.flow_logs_log_group_id == null`, is what drives this. A
# count has to be resolvable at plan time; when the caller passes the OCID of a
# log group it is creating in the same apply, that value is unknown at plan
# time, and "unknown == null" is itself unknown. Terraform then refuses with
# "The count value depends on resource attributes that cannot be determined
# until apply".
resource "oci_logging_log_group" "this" {
  count = var.flow_logs_enabled && var.create_flow_logs_log_group ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.name}-log-group"
  description    = "Flow log group created by the subnet module for ${var.name}."

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags
}

resource "oci_logging_log" "flow" {
  count = var.flow_logs_enabled ? 1 : 0

  display_name = "${var.name}-flowlog"
  log_group_id = local.flow_log_group_id
  log_type     = "SERVICE"
  is_enabled   = true

  retention_duration = var.flow_logs_retention_days

  configuration {
    compartment_id = var.compartment_id

    source {
      category    = "all"
      resource    = oci_core_subnet.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags

  lifecycle {
    precondition {
      condition     = var.create_flow_logs_log_group || var.flow_logs_log_group_id != null
      error_message = "With create_flow_logs_log_group = false you must pass flow_logs_log_group_id."
    }
  }
}
