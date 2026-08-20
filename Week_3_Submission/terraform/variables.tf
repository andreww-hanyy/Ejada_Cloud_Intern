###############################################################################
# Root variables
#
# The root module holds all the *values* for this particular lab. The two
# modules under ./modules hold the *structure*. Nothing lab-specific -- no
# CIDR, no shape, no name -- appears inside a module.
###############################################################################

# ---------------------------------------------------------------------------
# Provider / identity
# ---------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "Tenancy OCID."
  type        = string
}

variable "user_ocid" {
  description = "User OCID of the API signing user."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key."
  type        = string
}

variable "private_key_path" {
  description = "Path to the API signing private key. Keep this on an NTFS drive (C:) -- exFAT cannot hold the required file permissions."
  type        = string
}

variable "region" {
  description = "OCI region identifier."
  type        = string
  default     = "me-jeddah-1"
}

variable "compartment_id" {
  description = "Compartment OCID everything is created in."
  type        = string
}

# ---------------------------------------------------------------------------
# Naming / tagging
# ---------------------------------------------------------------------------

variable "prefix" {
  description = "Name prefix for every resource, e.g. ejada-w3-dev."
  type        = string
  default     = "ejada-w3-dev"
}

variable "freeform_tags" {
  description = "Freeform tags applied across the stack."
  type        = map(string)
  default = {
    project = "ejada-internship"
    week    = "3"
    owner   = "andrew-hany"
    managed = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Network addressing
#
# Sized per Oracle's reference layout for VCN-native pod networking:
# https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfigexample.htm
# ---------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "CIDR block of the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = <<-EOT
    CIDR block per subnet role. The pod subnet is deliberately large: with
    VCN-native pod networking every pod consumes a real VCN IP address.
  EOT
  type = object({
    api     = string
    workers = string
    pods    = string
    lb      = string
  })
  default = {
    api     = "10.0.0.0/29"
    workers = "10.0.1.0/24"
    lb      = "10.0.2.0/24"
    pods    = "10.0.32.0/19"
  }
}

variable "enable_flow_logs" {
  description = "Enable VCN flow logs on all four subnets. This is the 'Enable Logs' resource of the subnet module."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Flow log retention in days (30-day increments, 30..180)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "cluster_type" {
  description = "BASIC_CLUSTER or ENHANCED_CLUSTER."
  type        = string
  default     = "ENHANCED_CLUSTER"
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. v1.33.1. Null = newest available in the region."
  type        = string
  default     = null
}

variable "cni_type" {
  description = "OCI_VCN_IP_NATIVE (required by this lab) or FLANNEL_OVERLAY."
  type        = string
  default     = "OCI_VCN_IP_NATIVE"
}

variable "endpoint_is_public" {
  description = "Public API endpoint so kubectl works from your laptop / Cloud Shell."
  type        = bool
  default     = true
}

variable "services_cidr" {
  description = "CIDR for Kubernetes ClusterIP services."
  type        = string
  default     = "10.96.0.0/16"
}

variable "kubectl_source_cidr" {
  description = <<-EOT
    Who may reach the Kubernetes API on TCP/6443. 0.0.0.0/0 is convenient for a
    lab but is the single most important thing to tighten before anything real.
  EOT
  type        = string
  default     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Managed node pools. Passed straight through to the OKE module, minus the
    subnet OCIDs which the root wires in from the subnet modules.
  EOT
  type = map(object({
    shape                   = string
    size                    = number
    ocpus                   = optional(number)
    memory_in_gbs           = optional(number)
    boot_volume_size_in_gbs = optional(number, 60)
    max_pods_per_node       = optional(number, 31)
    ad_indexes              = optional(list(number), [0])
    node_labels             = optional(map(string), {})
    image_id                = optional(string)
    ssh_public_key          = optional(string)
  }))
  default = {
    app = {
      shape         = "VM.Standard.E4.Flex"
      size          = 2
      ocpus         = 2
      memory_in_gbs = 16
      node_labels   = { workload = "general" }
    }
  }
}

variable "cluster_addons" {
  description = "Optional OKE cluster add-ons, keyed by add-on name."
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
# Load balancer exposure
# ---------------------------------------------------------------------------

variable "app_ingress_ports" {
  description = "Ports the public load balancer subnet accepts from the internet. The Kubernetes Service publishes on these."
  type        = list(number)
  default     = [80, 443]
}

variable "app_source_cidr" {
  description = "Who may reach the application load balancer."
  type        = string
  default     = "0.0.0.0/0"
}
