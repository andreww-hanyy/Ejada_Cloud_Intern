###############################################################################
# Security and routing rule sets
#
# Every rule below is expressed in terms of var.subnet_cidrs and gateway IDs,
# so changing the address plan in terraform.tfvars re-wires the whole cluster
# with no edits here and none inside the modules.
#
# Rules follow Oracle's reference configuration for an OKE cluster with
# VCN-native pod networking, a public API endpoint, private workers and
# public load balancers.
###############################################################################

locals {
  ad_names = data.oci_identity_availability_domains.this.availability_domains[*].name

  cidr_api     = var.subnet_cidrs.api
  cidr_workers = var.subnet_cidrs.workers
  cidr_pods    = var.subnet_cidrs.pods
  cidr_lb      = var.subnet_cidrs.lb

  osn_cidr = data.oci_core_services.all_oci_services.services[0].cidr_block

  flow_log_group_id = var.enable_flow_logs ? oci_logging_log_group.flow_logs[0].id : null

  # -------------------------------------------------------------------------
  # Route tables
  # -------------------------------------------------------------------------

  route_public = [{
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
    description       = "Default route to the internet gateway"
  }]

  route_private = [
    {
      destination       = "0.0.0.0/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_nat_gateway.this.id
      description       = "Egress to the internet via NAT (no inbound)"
    },
    {
      destination       = local.osn_cidr
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.this.id
      description       = "Private path to the Oracle Services Network"
    },
  ]

  # -------------------------------------------------------------------------
  # Reusable rule fragments
  # -------------------------------------------------------------------------

  # ICMP type 3 code 4 = "fragmentation needed" -- required for path MTU
  # discovery. Without it, large packets silently disappear.
  icmp_pmtu_ingress = {
    protocol     = "1"
    source       = "0.0.0.0/0"
    icmp_options = { type = 3, code = 4 }
    description  = "Path MTU discovery"
  }

  icmp_pmtu_egress_osn = {
    protocol         = "1"
    destination      = local.osn_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    icmp_options     = { type = 3, code = 4 }
    description      = "Path MTU discovery to the Oracle Services Network"
  }

  egress_osn_all_tcp = {
    protocol         = "6"
    destination      = local.osn_cidr
    destination_type = "SERVICE_CIDR_BLOCK"
    description      = "Reach OKE, OCIR and other OCI services privately"
  }

  # -------------------------------------------------------------------------
  # API endpoint subnet (public /29)
  # -------------------------------------------------------------------------

  api_ingress = [
    { protocol = "6", source = local.cidr_workers, tcp_options = { min = 6443, max = 6443 }, description = "Workers -> Kubernetes API" },
    { protocol = "6", source = local.cidr_workers, tcp_options = { min = 12250, max = 12250 }, description = "Workers -> OKE control plane" },
    { protocol = "1", source = local.cidr_workers, icmp_options = { type = 3, code = 4 }, description = "Path MTU discovery from workers" },
    { protocol = "6", source = local.cidr_pods, tcp_options = { min = 6443, max = 6443 }, description = "Pods -> Kubernetes API" },
    { protocol = "6", source = local.cidr_pods, tcp_options = { min = 12250, max = 12250 }, description = "Pods -> OKE control plane" },
    { protocol = "6", source = var.kubectl_source_cidr, tcp_options = { min = 6443, max = 6443 }, description = "External kubectl access" },
  ]

  api_egress = [
    local.egress_osn_all_tcp,
    local.icmp_pmtu_egress_osn,
    # All TCP, not just 10250: aggregated API services and admission webhooks
    # listen on other host ports, and the control plane has to reach them.
    { protocol = "6", destination = local.cidr_workers, description = "Control plane -> worker nodes (kubelet, webhooks, aggregated APIs)" },
    { protocol = "1", destination = local.cidr_workers, icmp_options = { type = 3, code = 4 }, description = "Path MTU discovery to workers" },
    { protocol = "all", destination = local.cidr_pods, description = "Control plane <-> pods" },
  ]

  # -------------------------------------------------------------------------
  # Worker node subnet (private /24)
  # -------------------------------------------------------------------------

  workers_ingress = [
    { protocol = "all", source = local.cidr_workers, description = "Worker to worker (host-network traffic between nodes)" },
    { protocol = "6", source = local.cidr_api, tcp_options = { min = 10250, max = 10250 }, description = "Control plane -> kubelet" },
    { protocol = "all", source = local.cidr_pods, description = "Pods -> workers" },
    { protocol = "6", source = local.cidr_lb, tcp_options = { min = 30000, max = 32767 }, description = "Load balancer -> NodePort range" },
    { protocol = "6", source = local.cidr_lb, tcp_options = { min = 10256, max = 10256 }, description = "Load balancer -> kube-proxy health check" },
    local.icmp_pmtu_ingress,
  ]

  workers_egress = [
    { protocol = "all", destination = local.cidr_pods, description = "Workers <-> pods" },
    { protocol = "6", destination = local.cidr_api, tcp_options = { min = 6443, max = 6443 }, description = "Workers -> Kubernetes API" },
    { protocol = "6", destination = local.cidr_api, tcp_options = { min = 12250, max = 12250 }, description = "Workers -> OKE control plane" },
    local.egress_osn_all_tcp,
    local.icmp_pmtu_egress_osn,
    { protocol = "1", destination = "0.0.0.0/0", icmp_options = { type = 3, code = 4 }, description = "Path MTU discovery" },
    { protocol = "all", destination = "0.0.0.0/0", description = "Outbound via NAT: image pulls, yum, package repos" },
  ]

  # -------------------------------------------------------------------------
  # Pod subnet (private /19)
  # -------------------------------------------------------------------------

  pods_ingress = [
    { protocol = "all", source = local.cidr_workers, description = "Workers -> pods" },
    { protocol = "all", source = local.cidr_api, description = "Control plane -> pods" },
    { protocol = "all", source = local.cidr_pods, description = "Pod to pod" },
  ]

  pods_egress = [
    { protocol = "all", destination = local.cidr_pods, description = "Pod to pod" },
    { protocol = "6", destination = local.cidr_api, tcp_options = { min = 6443, max = 6443 }, description = "Pods -> Kubernetes API" },
    { protocol = "6", destination = local.cidr_api, tcp_options = { min = 12250, max = 12250 }, description = "Pods -> OKE control plane" },
    local.egress_osn_all_tcp,
    local.icmp_pmtu_egress_osn,
    { protocol = "all", destination = "0.0.0.0/0", description = "Outbound via NAT: image pulls and application traffic" },
  ]

  # -------------------------------------------------------------------------
  # Load balancer subnet (public /24)
  #
  # Built with a for-expression over var.app_ingress_ports: adding a port to
  # terraform.tfvars adds a rule, with no code change.
  # -------------------------------------------------------------------------

  lb_ingress = [
    for p in var.app_ingress_ports : {
      protocol    = "6"
      source      = var.app_source_cidr
      tcp_options = { min = p, max = p }
      description = "Public traffic to the application on port ${p}"
    }
  ]

  lb_egress = [
    { protocol = "6", destination = local.cidr_workers, tcp_options = { min = 30000, max = 32767 }, description = "Load balancer -> NodePort range" },
    { protocol = "6", destination = local.cidr_workers, tcp_options = { min = 10256, max = 10256 }, description = "Load balancer -> kube-proxy health check" },
  ]
}
