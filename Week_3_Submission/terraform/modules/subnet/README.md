# `modules/subnet`

An OCI subnet and the three things that always travel with it: its routing, its
packet filtering, and its flow logging.

```
oci_core_subnet
oci_core_route_table      (optional)
oci_core_security_list    (optional)
oci_logging_log           (optional)  [+ oci_logging_log_group, if create_flow_logs_log_group]
```

Nothing in this module is specific to Kubernetes, to this lab, or to any
address plan. It is "a subnet, done properly", and it is called four times in
this stack for four very different subnets.

## Usage

Minimal — a private subnet with no routes and no rules:

```hcl
module "subnet_data" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  name           = "app-data"
  cidr_block     = "10.0.5.0/24"
}
```

Realistic — the worker node subnet from this lab:

```hcl
module "subnet_workers" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  name       = "${var.prefix}-workers"
  cidr_block = "10.0.1.0/24"
  dns_label  = "workers"
  is_public  = false

  route_rules = [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_nat_gateway.this.id
      description       = "Egress via NAT"
    },
    {
      destination       = local.osn_cidr
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.this.id
      description       = "Oracle Services Network"
    },
  ]

  ingress_rules = [
    { protocol = "6",   source = "10.0.0.0/29",  tcp_options = { min = 10250, max = 10250 }, description = "Control plane -> kubelet" },
    { protocol = "all", source = "10.0.32.0/19",                                             description = "Pods -> workers" },
    { protocol = "1",   source = "0.0.0.0/0",    icmp_options = { type = 3, code = 4 },      description = "Path MTU discovery" },
  ]

  egress_rules = [
    { protocol = "all", destination = "0.0.0.0/0", description = "Outbound via NAT" },
  ]

  flow_logs_enabled          = true
  create_flow_logs_log_group = false
  flow_logs_log_group_id     = oci_logging_log_group.shared.id
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `compartment_id` | `string` | — | Compartment OCID. Validated to look like one. |
| `vcn_id` | `string` | — | VCN OCID. Validated. |
| `name` | `string` | — | Base name; every resource derives its display name from it. |
| `cidr_block` | `string` | — | Subnet CIDR. Validated with `cidrhost()`. |
| `dns_label` | `string` | `null` | ≤15 alphanumerics, starts with a letter. |
| `is_public` | `bool` | `false` | Drives both `prohibit_public_ip_on_vnic` and `prohibit_internet_ingress`. |
| `availability_domain` | `string` | `null` | `null` = regional subnet (what OKE needs). |
| `dhcp_options_id` | `string` | `null` | `null` = VCN default. |
| `create_route_table` | `bool` | `true` | Create one, or attach `route_table_id`. |
| `route_table_id` | `string` | `null` | Existing route table when not creating one. |
| `route_rules` | `list(object)` | `[]` | Rendered with a `dynamic` block. |
| `create_security_list` | `bool` | `true` | Create one, or use `security_list_ids`. |
| `security_list_ids` | `list(string)` | `[]` | Extra lists to attach. |
| `ingress_rules` | `list(object)` | `[]` | Protocol validated to `all`/`1`/`6`/`17`/`58`. |
| `egress_rules` | `list(object)` | `[]` | Same shape, keyed on `destination`. |
| `flow_logs_enabled` | `bool` | `true` | The "Enable Logs" resource. |
| `create_flow_logs_log_group` | `bool` | `true` | Create one, or write into `flow_logs_log_group_id`. |
| `flow_logs_log_group_id` | `string` | `null` | Existing group when not creating one. |
| `flow_logs_retention_days` | `number` | `30` | 30-day increments, 30–180. |
| `freeform_tags` / `defined_tags` | `map(string)` | `{}` | Applied to everything. |

### Rule object shape

```hcl
{
  protocol    = "all" | "1" (ICMP) | "6" (TCP) | "17" (UDP) | "58" (ICMPv6)
  source      = string   # ingress
  destination = string   # egress
  source_type      = optional(string, "CIDR_BLOCK")   # or SERVICE_CIDR_BLOCK
  destination_type = optional(string, "CIDR_BLOCK")
  stateless   = optional(bool, false)
  description = optional(string)
  tcp_options  = optional({ min, max, source_port_range = optional({ min, max }) })
  udp_options  = optional({ min, max, source_port_range = optional({ min, max }) })
  icmp_options = optional({ type, code = optional(number) })
}
```

Omit `tcp_options` / `udp_options` entirely to mean *all ports*.

## Outputs

| Name | Description |
|---|---|
| `subnet_id` | Subnet OCID |
| `subnet_name` | Display name |
| `cidr_block` | Echoed back so callers can build rules from outputs, not literals |
| `is_public` | Posture |
| `route_table_id` | Attached route table (created or supplied) |
| `security_list_ids` | All attached lists |
| `security_list_id` | The one created here, or `null` |
| `flow_log_id` | Flow log OCID, or `null` |
| `flow_log_group_id` | Log group holding it, or `null` |

## Notes

- **Regional by default.** `availability_domain` is `null` unless you set it.
  OKE requires regional subnets.
- **`precondition`** rejects `create_security_list = false` with an empty
  `security_list_ids` — a subnet with no filtering at all is almost never
  intended, and failing at plan time beats discovering it later.
- **Flow log source** is `service = "flowlogs"`, `source_type = "OCISERVICE"`,
  `category = "all"`, `log_type = "SERVICE"`. Not the resource's own service
  name — a common mistake.
- **Retention** must be a 30-day increment; the variable validates it rather
  than letting the API reject the apply.
