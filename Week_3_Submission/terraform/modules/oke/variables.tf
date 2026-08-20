###############################################################################
# modules/oke -- input contract
#
# The module knows how to build an OKE cluster. It knows nothing about *this*
# lab: no CIDRs, no compartment, no subnet OCIDs, no shapes are baked in.
###############################################################################

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "compartment_id" {
  description = "OCID of the compartment for the cluster and node pools."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN hosting the cluster."
  type        = string
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Cluster display name. Node pools derive their names from it unless overridden."
  type        = string
}

variable "cluster_type" {
  description = "BASIC_CLUSTER or ENHANCED_CLUSTER. Enhanced is required for cluster add-on management, workload identity and higher node limits."
  type        = string
  default     = "ENHANCED_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "cluster_type must be BASIC_CLUSTER or ENHANCED_CLUSTER."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. \"v1.33.1\". Leave null to take the newest version the region advertises."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", coalesce(var.kubernetes_version, "v0.0.0")))
    error_message = "kubernetes_version must look like v1.33.1, or be null."
  }
}

variable "cni_type" {
  description = <<-EOT
    Pod networking mode.
      OCI_VCN_IP_NATIVE -- pods get real VCN IPs from a dedicated pod subnet
      FLANNEL_OVERLAY   -- pods get overlay IPs from pods_cidr
    This lab uses OCI_VCN_IP_NATIVE; the module supports both so it can be
    reused on clusters that do not need VCN-native pods.
  EOT
  type        = string
  default     = "OCI_VCN_IP_NATIVE"

  validation {
    condition     = contains(["OCI_VCN_IP_NATIVE", "FLANNEL_OVERLAY"], var.cni_type)
    error_message = "cni_type must be OCI_VCN_IP_NATIVE or FLANNEL_OVERLAY."
  }
}

# ---------------------------------------------------------------------------
# Cluster networking
# ---------------------------------------------------------------------------

variable "endpoint_subnet_id" {
  description = "OCID of the regional subnet hosting the Kubernetes API endpoint."
  type        = string
}

variable "endpoint_is_public" {
  description = "Give the API endpoint a public IP so kubectl works from outside the VCN."
  type        = bool
  default     = true
}

variable "endpoint_nsg_ids" {
  description = "NSG OCIDs applied to the API endpoint. Empty list = security lists only."
  type        = list(string)
  default     = []
}

variable "service_lb_subnet_ids" {
  description = "Subnet OCIDs where Kubernetes Service type=LoadBalancer provisions OCI load balancers."
  type        = list(string)
  default     = []
}

variable "service_lb_backend_nsg_ids" {
  description = "NSG OCIDs attached to the backends of service-managed load balancers."
  type        = list(string)
  default     = []
}

variable "services_cidr" {
  description = "CIDR for Kubernetes ClusterIP services. Must not overlap the VCN."
  type        = string
  default     = "10.96.0.0/16"

  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "services_cidr must be a valid IPv4 CIDR."
  }
}

variable "pods_cidr" {
  description = "Overlay CIDR for pods. Only meaningful when cni_type = FLANNEL_OVERLAY; ignored (sent as null) for VCN-native."
  type        = string
  default     = "10.244.0.0/16"
}

# ---------------------------------------------------------------------------
# Cluster options
# ---------------------------------------------------------------------------

variable "kms_key_id" {
  description = "Vault key OCID for envelope-encrypting Kubernetes secrets at rest. Null uses Oracle-managed keys."
  type        = string
  default     = null
}

variable "is_pod_security_policy_enabled" {
  description = "Enable the PodSecurityPolicy admission controller (legacy; off by default)."
  type        = bool
  default     = false
}

variable "cluster_addons" {
  description = <<-EOT
    Cluster add-ons to manage declaratively (ENHANCED_CLUSTER only), keyed by
    add-on name. Example:
      cluster_addons = {
        CertManager = { version = "v1.15.1" }
        ClusterAutoscaler = {
          configurations = [{ key = "nodes.max", value = "5" }]
        }
      }
  EOT
  type = map(object({
    version                          = optional(string)
    remove_addon_resources_on_delete = optional(bool, true)
    configurations = optional(list(object({
      key   = string
      value = string
    })), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Managed node pools, keyed by short name. Everything about a pool is
    caller-supplied; the module only supplies safe defaults via optional().

    Example:
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
  EOT
  type = map(object({
    # placement
    node_subnet_id       = string
    availability_domains = list(string)
    fault_domains        = optional(list(string))

    # sizing
    shape         = string
    size          = number
    ocpus         = optional(number)
    memory_in_gbs = optional(number)

    # VCN-native pod networking
    pod_subnet_ids    = optional(list(string), [])
    pod_nsg_ids       = optional(list(string), [])
    max_pods_per_node = optional(number, 31)

    # image
    image_id                = optional(string)
    boot_volume_size_in_gbs = optional(number, 60)
    kubernetes_version      = optional(string)

    # misc
    node_nsg_ids   = optional(list(string), [])
    node_labels    = optional(map(string), {})
    ssh_public_key = optional(string)
    display_name   = optional(string)

    eviction = optional(object({
      grace_duration              = optional(string, "PT60M")
      is_force_action_after_grace = optional(bool, true)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, np in var.node_pools : np.size >= 1 && length(np.availability_domains) > 0
    ])
    error_message = "Every node pool must have size >= 1 and at least one availability domain (an empty availability_domains list produces a node pool with no placement config, which the API rejects)."
  }
}

# ---------------------------------------------------------------------------
# Cosmetic
# ---------------------------------------------------------------------------

variable "region_for_kubeconfig_hint" {
  description = "Region identifier (e.g. me-jeddah-1) used only to render the kubeconfig_command output. Not used to create anything."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

variable "freeform_tags" {
  description = "Freeform tags applied to the cluster and every node pool."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags applied to the cluster and every node pool."
  type        = map(string)
  default     = {}
}
