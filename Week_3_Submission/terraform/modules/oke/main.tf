###############################################################################
# modules/oke
#
#   * oci_containerengine_cluster    -- control plane, CNI, endpoint, LB subnets
#   * oci_containerengine_node_pool  -- one per entry in var.node_pools (for_each)
#   * oci_containerengine_addon      -- optional, one per entry in var.cluster_addons
#
# Techniques on show here:
#   * for_each over a map        -- N node pools / add-ons from one block
#   * dynamic blocks             -- placement_configs, initial_node_labels,
#                                   node_shape_config, eviction settings,
#                                   configurations
#   * conditional expressions    -- pods_cidr only applies to FLANNEL_OVERLAY;
#                                   pod network details only to VCN-native
#   * data-source driven defaults-- newest k8s version and matching OKE image
#                                   are discovered, not hardcoded
###############################################################################

# ---------------------------------------------------------------------------
# Discovery: available Kubernetes versions and node images
# ---------------------------------------------------------------------------

data "oci_containerengine_cluster_option" "this" {
  cluster_option_id = "all"
  compartment_id    = var.compartment_id
}

data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  # The API returns versions ascending, so the last element is the newest.
  available_versions = data.oci_containerengine_cluster_option.this.kubernetes_versions
  cluster_version    = coalesce(var.kubernetes_version, element(local.available_versions, length(local.available_versions) - 1))

  # "v1.33.1" -> "1.33.1"; OKE image names embed the version as OKE-1.33.1-<build>.
  version_tag = replace(local.cluster_version, "v", "")

  is_vcn_native = var.cni_type == "OCI_VCN_IP_NATIVE"

  # Per-pool image shortlist: OKE images for this Kubernetes version, matching
  # the pool's CPU architecture, excluding GPU variants. Ampere/Arm shapes
  # (A1, A2) need aarch64 images; everything else needs x86_64.
  candidate_images = {
    for k, np in var.node_pools : k => [
      for s in data.oci_containerengine_node_pool_option.this.sources :
      s.image_id
      if can(regex("OKE-${local.version_tag}", s.source_name))
      && !can(regex("(?i)GPU", s.source_name))
      && (
        length(regexall("(?i)(A1|A2|Ampere)", np.shape)) > 0
        ? can(regex("(?i)aarch64", s.source_name))
        : !can(regex("(?i)aarch64", s.source_name))
      )
    ]
  }

  # Caller's explicit image_id wins; otherwise the newest match (OKE publishes
  # sources oldest-first). try() turns "no match" into null, which the node
  # pool's precondition then reports with a useful message.
  pool_images = {
    for k, np in var.node_pools : k => (
      np.image_id != null
      ? np.image_id
      : try(local.candidate_images[k][length(local.candidate_images[k]) - 1], null)
    )
  }

  common_tags = merge(var.freeform_tags, { "tf-module" = "oke" })

  # An empty map is not the same as "unset". `defined_tags = {}` tells OCI to
  # remove every defined tag -- which fights the tenancy's Oracle-Tags default
  # namespace, where CreatedBy and CreatedOn are applied automatically at
  # creation, and leaves a permanent diff on every resource the module makes.
  # defined_tags is Optional+Computed in the provider schema, so null means
  # "leave it to the provider" and the caller's tags still win when supplied.
  defined_tags = length(var.defined_tags) > 0 ? var.defined_tags : null
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  vcn_id             = var.vcn_id
  name               = var.cluster_name
  kubernetes_version = local.cluster_version
  type               = var.cluster_type

  cluster_pod_network_options {
    cni_type = var.cni_type
  }

  endpoint_config {
    subnet_id            = var.endpoint_subnet_id
    is_public_ip_enabled = var.endpoint_is_public
    nsg_ids              = var.endpoint_nsg_ids
  }

  kms_key_id = var.kms_key_id

  options {
    service_lb_subnet_ids = var.service_lb_subnet_ids

    kubernetes_network_config {
      services_cidr = var.services_cidr
      # pods_cidr is an overlay concept: send it only for FLANNEL_OVERLAY,
      # otherwise null so OKE ignores it.
      pods_cidr = local.is_vcn_native ? null : var.pods_cidr
    }

    admission_controller_options {
      is_pod_security_policy_enabled = var.is_pod_security_policy_enabled
    }

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    dynamic "service_lb_config" {
      for_each = length(var.service_lb_backend_nsg_ids) > 0 ? [1] : []
      content {
        backend_nsg_ids = var.service_lb_backend_nsg_ids
        freeform_tags   = local.common_tags
      }
    }

    persistent_volume_config {
      freeform_tags = local.common_tags
    }
  }

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags

  lifecycle {
    precondition {
      condition = !local.is_vcn_native || alltrue([
        for k, np in var.node_pools : length(np.pod_subnet_ids) > 0
      ])
      error_message = "cni_type = OCI_VCN_IP_NATIVE requires every node pool to set pod_subnet_ids."
    }
  }
}

# ---------------------------------------------------------------------------
# Managed node pools
# ---------------------------------------------------------------------------

resource "oci_containerengine_node_pool" "this" {
  for_each = var.node_pools

  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  name               = coalesce(each.value.display_name, "${var.cluster_name}-${each.key}")
  node_shape         = each.value.shape
  kubernetes_version = coalesce(each.value.kubernetes_version, local.cluster_version)
  ssh_public_key     = each.value.ssh_public_key

  node_config_details {
    size = each.value.size

    # One placement_configs block per availability domain the caller listed.
    dynamic "placement_configs" {
      for_each = each.value.availability_domains
      content {
        availability_domain = placement_configs.value
        subnet_id           = each.value.node_subnet_id
        fault_domains       = each.value.fault_domains
      }
    }

    # Pod network details only make sense for VCN-native pod networking.
    dynamic "node_pool_pod_network_option_details" {
      for_each = local.is_vcn_native ? [1] : []
      content {
        cni_type          = var.cni_type
        pod_subnet_ids    = each.value.pod_subnet_ids
        pod_nsg_ids       = each.value.pod_nsg_ids
        max_pods_per_node = each.value.max_pods_per_node
      }
    }

    nsg_ids       = each.value.node_nsg_ids
    freeform_tags = local.common_tags
    defined_tags  = local.defined_tags
  }

  # Flex shapes need an explicit OCPU/memory split; fixed shapes must not have one.
  dynamic "node_shape_config" {
    for_each = each.value.ocpus == null && each.value.memory_in_gbs == null ? [] : [1]
    content {
      ocpus         = each.value.ocpus
      memory_in_gbs = each.value.memory_in_gbs
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.pool_images[each.key]
    boot_volume_size_in_gbs = each.value.boot_volume_size_in_gbs
  }

  # One initial_node_labels block per key/value pair in node_labels.
  dynamic "initial_node_labels" {
    for_each = each.value.node_labels
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  dynamic "node_eviction_node_pool_settings" {
    for_each = each.value.eviction == null ? [] : [each.value.eviction]
    content {
      eviction_grace_duration              = node_eviction_node_pool_settings.value.grace_duration
      is_force_action_after_grace_duration = node_eviction_node_pool_settings.value.is_force_action_after_grace
    }
  }

  freeform_tags = local.common_tags
  defined_tags  = local.defined_tags

  lifecycle {
    precondition {
      condition     = local.pool_images[each.key] != null
      error_message = "No OKE node image found for shape ${each.value.shape} at version ${local.cluster_version}. Set image_id on the node pool explicitly."
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ---------------------------------------------------------------------------
# Optional cluster add-ons (ENHANCED_CLUSTER only)
# ---------------------------------------------------------------------------

resource "oci_containerengine_addon" "this" {
  for_each = var.cluster_type == "ENHANCED_CLUSTER" ? var.cluster_addons : {}

  cluster_id                       = oci_containerengine_cluster.this.id
  addon_name                       = each.key
  version                          = each.value.version
  remove_addon_resources_on_delete = each.value.remove_addon_resources_on_delete

  dynamic "configurations" {
    for_each = each.value.configurations
    content {
      key   = configurations.value.key
      value = configurations.value.value
    }
  }
}
