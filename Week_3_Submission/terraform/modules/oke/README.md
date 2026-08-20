# `modules/oke`

An OKE cluster, its managed node pools, and optional cluster add-ons.

```
oci_containerengine_cluster
oci_containerengine_node_pool    (one per entry in var.node_pools)
oci_containerengine_addon        (one per entry in var.cluster_addons)
```

The module knows how to build a cluster. It knows nothing about this lab: no
compartment, no CIDR, no shape, no subnet OCID and no name is baked in.

## Usage

```hcl
module "oke" {
  source = "./modules/oke"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  cluster_name   = "${var.prefix}-oke"

  cni_type              = "OCI_VCN_IP_NATIVE"
  endpoint_subnet_id    = module.subnet_api.subnet_id
  endpoint_is_public    = true
  service_lb_subnet_ids = [module.subnet_lb.subnet_id]

  node_pools = {
    app = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory_in_gbs        = 16
      size                 = 2
      node_subnet_id       = module.subnet_workers.subnet_id
      pod_subnet_ids       = [module.subnet_pods.subnet_id]
      availability_domains = [local.ad_names[0]]
      node_labels          = { workload = "general" }
    }
  }
}
```

Two pools, one of them Ampere — same module, no changes:

```hcl
node_pools = {
  general = {
    shape = "VM.Standard.E4.Flex", ocpus = 2, memory_in_gbs = 16, size = 2
    node_subnet_id = module.subnet_workers.subnet_id
    pod_subnet_ids = [module.subnet_pods.subnet_id]
    availability_domains = [local.ad_names[0]]
  }
  arm = {
    shape = "VM.Standard.A1.Flex", ocpus = 2, memory_in_gbs = 12, size = 1
    node_subnet_id = module.subnet_workers.subnet_id
    pod_subnet_ids = [module.subnet_pods.subnet_id]
    availability_domains = [local.ad_names[0]]
    node_labels = { arch = "arm64" }
  }
}
```

The `arm` pool automatically gets an `aarch64` OKE image; the module detects it
from the shape name.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `compartment_id` | `string` | — | Compartment OCID |
| `vcn_id` | `string` | — | VCN OCID |
| `cluster_name` | `string` | — | Cluster display name; node pool names derive from it |
| `cluster_type` | `string` | `ENHANCED_CLUSTER` | `BASIC_CLUSTER` or `ENHANCED_CLUSTER` |
| `kubernetes_version` | `string` | `null` | `null` = newest the region advertises |
| `cni_type` | `string` | `OCI_VCN_IP_NATIVE` | or `FLANNEL_OVERLAY` |
| `endpoint_subnet_id` | `string` | — | Regional subnet for the API endpoint |
| `endpoint_is_public` | `bool` | `true` | Public IP on the API endpoint |
| `endpoint_nsg_ids` | `list(string)` | `[]` | NSGs on the endpoint |
| `service_lb_subnet_ids` | `list(string)` | `[]` | Where `Service type=LoadBalancer` provisions LBs |
| `service_lb_backend_nsg_ids` | `list(string)` | `[]` | NSGs on LB backends |
| `services_cidr` | `string` | `10.96.0.0/16` | ClusterIP range; must not overlap the VCN |
| `pods_cidr` | `string` | `10.244.0.0/16` | Only used for `FLANNEL_OVERLAY` |
| `kms_key_id` | `string` | `null` | Vault key for encrypting secrets at rest |
| `is_pod_security_policy_enabled` | `bool` | `false` | Legacy PSP admission controller |
| `cluster_addons` | `map(object)` | `{}` | Add-ons (ENHANCED_CLUSTER only) |
| `node_pools` | `map(object)` | `{}` | See below |
| `region_for_kubeconfig_hint` | `string` | `""` | Cosmetic — renders the kubeconfig command |
| `freeform_tags` / `defined_tags` | `map(string)` | `{}` | Applied to everything |

### `node_pools` entry

```hcl
{
  node_subnet_id       = string          # required
  availability_domains = list(string)    # required, one placement block each
  shape                = string          # required
  size                 = number          # required, >= 1

  ocpus         = optional(number)       # flex shapes only
  memory_in_gbs = optional(number)

  pod_subnet_ids    = optional(list(string), [])   # required for VCN-native
  pod_nsg_ids       = optional(list(string), [])
  max_pods_per_node = optional(number, 31)

  image_id                = optional(string)   # null = auto-discover
  boot_volume_size_in_gbs = optional(number, 60)
  kubernetes_version      = optional(string)   # null = cluster version

  fault_domains  = optional(list(string))
  node_nsg_ids   = optional(list(string), [])
  node_labels    = optional(map(string), {})
  ssh_public_key = optional(string)
  display_name   = optional(string)

  eviction = optional(object({
    grace_duration              = optional(string, "PT60M")
    is_force_action_after_grace = optional(bool, true)
  }))
}
```

## Outputs

| Name | Description |
|---|---|
| `cluster_id` | Cluster OCID |
| `cluster_name` | Display name |
| `kubernetes_version` | Version actually deployed |
| `cni_type` | Pod networking mode in effect |
| `public_endpoint` / `private_endpoint` | API endpoints |
| `node_pool_ids` | Map of pool key → OCID |
| `node_pool_images` | Map of pool key → resolved image OCID |
| `addon_names` | Add-ons under Terraform management |
| `kubeconfig_command` | The `oci ce cluster create-kubeconfig` command to run |

## Notes

**The kubeconfig is not an output.** Emitting it would store a working cluster
credential in plain text inside `terraform.tfstate`. The module outputs the
command to generate one instead.

**Version and image discovery.** `oci_containerengine_cluster_option` supplies
the available Kubernetes versions and `oci_containerengine_node_pool_option`
the published OKE node images. The module takes the newest version unless you
pin one, then filters images by that version and by CPU architecture inferred
from the shape name (`A1`/`A2`/`Ampere` → `aarch64`), excluding GPU images.
`image_id` on a pool overrides all of it.

**Preconditions, not surprises.**
- `cni_type = OCI_VCN_IP_NATIVE` with a pool missing `pod_subnet_ids` fails at
  plan time with a sentence, not 15 minutes into an apply with an API error.
- No image found for a shape/version combination fails the same way, and tells
  you to set `image_id`.

**`pods_cidr` is sent as `null` for VCN-native**, because it is an overlay
concept that does not apply when pods hold real VCN addresses.

**Node pools use `for_each`, not `count`**, so pools have stable string keys.
Removing one pool from the map does not renumber and recreate the others.

**Version and image drift — know about this before you leave a cluster running.**
`kubernetes_version` is updatable on both the cluster and the node pool, and
`node_source_details.image_id` is updatable rather than force-new. So while
`kubernetes_version` is left `null`, the module re-resolves "newest available"
on *every* plan: the day OKE publishes a new version, an unrelated
`terraform apply` proposes a control-plane upgrade and a node image swap. That
is convenient on day one and a bad surprise on day ninety. Pin
`kubernetes_version` once the cluster exists. If you also want the node image
frozen against new OKE builds, add to the node pool resource:

```hcl
lifecycle {
  ignore_changes = [node_source_details[0].image_id]
}
```

It is left out of the module by default because a module should not silently
stop tracking a value the caller may want tracked.

**Timeouts are 60 minutes.** OKE node pools genuinely take 10–20 minutes and
occasionally longer; the provider default is 50, which is close enough to the
edge to be worth raising.
