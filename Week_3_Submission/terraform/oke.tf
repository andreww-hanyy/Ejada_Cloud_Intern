###############################################################################
# OKE cluster
#
# The root's only job here is translating lab-level intent (var.node_pools,
# which talks about shapes and AD indexes) into the module's contract, which
# talks about subnet OCIDs and AD names.
###############################################################################

module "oke" {
  source = "./modules/oke"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  cluster_name       = "${var.prefix}-oke"
  cluster_type       = var.cluster_type
  kubernetes_version = var.kubernetes_version
  cni_type           = var.cni_type

  endpoint_subnet_id    = module.subnet_api.subnet_id
  endpoint_is_public    = var.endpoint_is_public
  service_lb_subnet_ids = [module.subnet_lb.subnet_id]
  services_cidr         = var.services_cidr

  # Lab intent -> module contract. AD *indexes* in tfvars become AD *names*
  # here, so the tfvars file stays portable between regions.
  node_pools = {
    for k, np in var.node_pools : k => {
      shape                   = np.shape
      size                    = np.size
      ocpus                   = np.ocpus
      memory_in_gbs           = np.memory_in_gbs
      boot_volume_size_in_gbs = np.boot_volume_size_in_gbs
      max_pods_per_node       = np.max_pods_per_node
      image_id                = np.image_id
      ssh_public_key          = np.ssh_public_key
      node_labels             = np.node_labels

      node_subnet_id       = module.subnet_workers.subnet_id
      pod_subnet_ids       = [module.subnet_pods.subnet_id]
      availability_domains = [for i in np.ad_indexes : local.ad_names[i]]
    }
  }

  cluster_addons = var.cluster_addons

  region_for_kubeconfig_hint = var.region
  freeform_tags              = var.freeform_tags
}
