###############################################################################
# modules/subnet -- input contract
#
# Design rule for this module: NOTHING is hardcoded. Every name, CIDR, rule,
# flag and tag is supplied by the caller. The module owns the *shape* of the
# resources; the root configuration owns the *values*.
###############################################################################

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "compartment_id" {
  description = "OCID of the compartment that will own the subnet, route table, security list and log resources."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_id))
    error_message = "compartment_id must be a compartment or tenancy OCID."
  }
}

variable "vcn_id" {
  description = "OCID of the VCN the subnet is created in."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.vcn\\.", var.vcn_id))
    error_message = "vcn_id must be a VCN OCID."
  }
}

variable "availability_domain" {
  description = "AD name for an AD-specific subnet. Leave null (the default) to create a regional subnet, which is what OKE requires."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Subnet
# ---------------------------------------------------------------------------

variable "name" {
  description = "Base name. Every resource in the module derives its display name from this, so one variable renames the whole set."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. 10.0.1.0/24."
  }
}

variable "dns_label" {
  description = "DNS label for the subnet (<=15 alphanumeric chars, must start with a letter). Null disables DNS resolution for the subnet."
  type        = string
  default     = null

  validation {
    condition     = var.dns_label == null || can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", coalesce(var.dns_label, "x")))
    error_message = "dns_label must start with a letter and contain at most 15 alphanumeric characters."
  }
}

variable "is_public" {
  description = <<-EOT
    Single switch that drives both public/private behaviours of the subnet:
      true  -> VNICs may get public IPs and internet ingress is allowed
      false -> no public IPs, no internet ingress (private subnet)
  EOT
  type        = bool
  default     = false
}

variable "dhcp_options_id" {
  description = "OCID of a DHCP options set to attach. Null uses the VCN default."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Route table
# ---------------------------------------------------------------------------

variable "create_route_table" {
  description = "Create a dedicated route table for this subnet. Set to false to attach an existing one via route_table_id."
  type        = bool
  default     = true
}

variable "route_table_id" {
  description = "OCID of an existing route table to attach when create_route_table = false. Null attaches the VCN default route table."
  type        = string
  default     = null
}

variable "route_rules" {
  description = <<-EOT
    Route rules rendered into the module's route table with a dynamic block.
    Example:
      route_rules = [{
        destination       = "0.0.0.0/0"
        destination_type  = "CIDR_BLOCK"
        network_entity_id = oci_core_nat_gateway.this.id
        description       = "Egress to the internet via NAT"
      }]
  EOT
  type = list(object({
    destination       = string
    network_entity_id = string
    destination_type  = optional(string, "CIDR_BLOCK")
    description       = optional(string)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Security list
# ---------------------------------------------------------------------------

variable "create_security_list" {
  description = "Create a dedicated security list for this subnet. Set to false to attach existing lists via security_list_ids."
  type        = bool
  default     = true
}

variable "security_list_ids" {
  description = "Extra security list OCIDs to attach to the subnet, in addition to (or instead of) the one this module creates."
  type        = list(string)
  default     = []
}

variable "ingress_rules" {
  description = <<-EOT
    Ingress rules for the module's security list, rendered with nested dynamic
    blocks. Only set the *_options object matching the protocol.

      protocol: "all" | "1" (ICMP) | "6" (TCP) | "17" (UDP) | "58" (ICMPv6)

    Omitting tcp_options/udp_options means "all ports".

    Example:
      ingress_rules = [
        { protocol = "6", source = "0.0.0.0/0", tcp_options = { min = 6443, max = 6443 }, description = "Public kubectl" },
        { protocol = "1", source = "0.0.0.0/0", icmp_options = { type = 3, code = 4 },    description = "Path MTU discovery" },
        { protocol = "all", source = "10.0.32.0/19",                                       description = "Pod to pod" },
      ]
  EOT
  type = list(object({
    protocol    = string
    source      = string
    source_type = optional(string, "CIDR_BLOCK")
    stateless   = optional(bool, false)
    description = optional(string)
    tcp_options = optional(object({
      min               = optional(number)
      max               = optional(number)
      source_port_range = optional(object({ min = number, max = number }))
    }))
    udp_options = optional(object({
      min               = optional(number)
      max               = optional(number)
      source_port_range = optional(object({ min = number, max = number }))
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.ingress_rules : contains(["all", "1", "6", "17", "58"], r.protocol)])
    error_message = "ingress_rules protocol must be one of: all, 1 (ICMP), 6 (TCP), 17 (UDP), 58 (ICMPv6)."
  }
}

variable "egress_rules" {
  description = "Egress rules for the module's security list. Same object shape as ingress_rules, but keyed on destination instead of source."
  type = list(object({
    protocol         = string
    destination      = string
    destination_type = optional(string, "CIDR_BLOCK")
    stateless        = optional(bool, false)
    description      = optional(string)
    tcp_options = optional(object({
      min               = optional(number)
      max               = optional(number)
      source_port_range = optional(object({ min = number, max = number }))
    }))
    udp_options = optional(object({
      min               = optional(number)
      max               = optional(number)
      source_port_range = optional(object({ min = number, max = number }))
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.egress_rules : contains(["all", "1", "6", "17", "58"], r.protocol)])
    error_message = "egress_rules protocol must be one of: all, 1 (ICMP), 6 (TCP), 17 (UDP), 58 (ICMPv6)."
  }
}

# ---------------------------------------------------------------------------
# Flow logs
# ---------------------------------------------------------------------------

variable "flow_logs_enabled" {
  description = "Enable VCN flow logs on this subnet (Logging service, log_type = SERVICE, source service = flowlogs)."
  type        = bool
  default     = true
}

variable "create_flow_logs_log_group" {
  description = <<-EOT
    Create a log group for this subnet's flow log, or write into the one handed
    in as flow_logs_log_group_id.

    This is a separate flag rather than being inferred from
    "flow_logs_log_group_id == null" because `count` must be resolvable at plan
    time, and the OCID of a log group the caller is creating in the same run is
    not known until apply. Comparing an unknown value to null yields an unknown
    boolean, which `count` cannot accept.

    Same create_X / X_id pairing as create_route_table and create_security_list.
  EOT
  type        = bool
  default     = true
}

variable "flow_logs_log_group_id" {
  description = <<-EOT
    OCID of an existing log group to write flow logs into. Pass one from the
    root module, together with create_flow_logs_log_group = false, so every
    subnet shares a single group.
  EOT
  type        = string
  default     = null
}

variable "flow_logs_retention_days" {
  description = "Flow log retention in days. OCI accepts 30-day increments from 30 to 180."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be one of 30, 60, 90, 120, 150, 180."
  }
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "freeform_tags" {
  description = "Freeform tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}
