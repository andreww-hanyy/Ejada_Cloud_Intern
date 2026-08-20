output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.this.id
}

output "cluster_name" {
  description = "Cluster display name."
  value       = oci_containerengine_cluster.this.name
}

output "kubernetes_version" {
  description = "Kubernetes version actually deployed (resolved from the region when the caller left it null)."
  value       = oci_containerengine_cluster.this.kubernetes_version
}

output "cni_type" {
  description = "Pod networking mode in effect."
  value       = var.cni_type
}

output "public_endpoint" {
  description = "Public Kubernetes API endpoint, or null when the endpoint is private."
  value       = try(oci_containerengine_cluster.this.endpoints[0].public_endpoint, null)
}

output "private_endpoint" {
  description = "Private Kubernetes API endpoint."
  value       = try(oci_containerengine_cluster.this.endpoints[0].private_endpoint, null)
}

output "node_pool_ids" {
  description = "Map of node pool key -> OCID."
  value       = { for k, np in oci_containerengine_node_pool.this : k => np.id }
}

output "node_pool_images" {
  description = "Map of node pool key -> image OCID actually used, so the resolved image is visible without digging through state."
  value       = local.pool_images
}

output "addon_names" {
  description = "Names of the cluster add-ons managed by Terraform."
  value       = keys(oci_containerengine_addon.this)
}

output "kubeconfig_command" {
  description = <<-EOT
    Command that writes a kubeconfig for this cluster. The kubeconfig itself is
    deliberately NOT emitted as a Terraform output: doing so would store a
    cluster credential in plain text inside terraform.tfstate.
  EOT
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.this.id} --file $HOME/.kube/config --region ${var.region_for_kubeconfig_hint} --token-version 2.0.0 --kube-endpoint ${var.endpoint_is_public ? "PUBLIC_ENDPOINT" : "PRIVATE_ENDPOINT"}"
}
