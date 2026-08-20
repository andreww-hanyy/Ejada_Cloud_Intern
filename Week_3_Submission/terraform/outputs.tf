###############################################################################
# Outputs -- everything the lab steps after `terraform apply` need.
###############################################################################

output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.this.id
}

output "subnets" {
  description = "Every subnet the stack created: OCID, CIDR and posture."
  value = {
    api = {
      id        = module.subnet_api.subnet_id
      cidr      = module.subnet_api.cidr_block
      is_public = module.subnet_api.is_public
    }
    workers = {
      id        = module.subnet_workers.subnet_id
      cidr      = module.subnet_workers.cidr_block
      is_public = module.subnet_workers.is_public
    }
    pods = {
      id        = module.subnet_pods.subnet_id
      cidr      = module.subnet_pods.cidr_block
      is_public = module.subnet_pods.is_public
    }
    lb = {
      id        = module.subnet_lb.subnet_id
      cidr      = module.subnet_lb.cidr_block
      is_public = module.subnet_lb.is_public
    }
  }
}

output "lb_subnet_id" {
  description = "Load balancer subnet OCID. Paste this into the Service annotation in k8s/30-service-lb.yaml if you want to pin the LB explicitly."
  value       = module.subnet_lb.subnet_id
}

output "flow_log_ids" {
  description = "Flow log OCIDs per subnet, proving the 'Enable Logs' resource of the subnet module ran."
  value = {
    api     = module.subnet_api.flow_log_id
    workers = module.subnet_workers.flow_log_id
    pods    = module.subnet_pods.flow_log_id
    lb      = module.subnet_lb.flow_log_id
  }
}

output "cluster_id" {
  description = "OKE cluster OCID."
  value       = module.oke.cluster_id
}

output "kubernetes_version" {
  description = "Kubernetes version deployed."
  value       = module.oke.kubernetes_version
}

output "cluster_public_endpoint" {
  description = "Public Kubernetes API endpoint."
  value       = module.oke.public_endpoint
}

output "node_pool_ids" {
  description = "Node pool OCIDs."
  value       = module.oke.node_pool_ids
}

output "node_pool_images" {
  description = "OKE node image resolved for each pool."
  value       = module.oke.node_pool_images
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = module.oke.kubeconfig_command
}
