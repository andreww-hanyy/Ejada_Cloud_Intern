###############################################################################
# Four subnets, four calls to the same module.
#
# Each call passes a different address, a different rule set and a different
# public/private posture. The module code is identical for all four -- that is
# the point of the exercise.
###############################################################################

module "subnet_api" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  name       = "${var.prefix}-api"
  cidr_block = local.cidr_api
  dns_label  = "api"
  is_public  = true

  route_rules   = local.route_public
  ingress_rules = local.api_ingress
  egress_rules  = local.api_egress

  # The root owns the one shared log group, so every call turns the module's
  # own off. This is what makes the plan show 1 log group and not 5.
  flow_logs_enabled          = var.enable_flow_logs
  create_flow_logs_log_group = false
  flow_logs_log_group_id     = local.flow_log_group_id
  flow_logs_retention_days   = var.flow_logs_retention_days

  freeform_tags = merge(var.freeform_tags, { role = "k8s-api-endpoint" })
}

module "subnet_workers" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  name       = "${var.prefix}-workers"
  cidr_block = local.cidr_workers
  dns_label  = "workers"
  is_public  = false

  route_rules   = local.route_private
  ingress_rules = local.workers_ingress
  egress_rules  = local.workers_egress

  # The root owns the one shared log group, so every call turns the module's
  # own off. This is what makes the plan show 1 log group and not 5.
  flow_logs_enabled          = var.enable_flow_logs
  create_flow_logs_log_group = false
  flow_logs_log_group_id     = local.flow_log_group_id
  flow_logs_retention_days   = var.flow_logs_retention_days

  freeform_tags = merge(var.freeform_tags, { role = "k8s-workers" })
}

module "subnet_pods" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  name       = "${var.prefix}-pods"
  cidr_block = local.cidr_pods
  dns_label  = "pods"
  is_public  = false

  route_rules   = local.route_private
  ingress_rules = local.pods_ingress
  egress_rules  = local.pods_egress

  # The root owns the one shared log group, so every call turns the module's
  # own off. This is what makes the plan show 1 log group and not 5.
  flow_logs_enabled          = var.enable_flow_logs
  create_flow_logs_log_group = false
  flow_logs_log_group_id     = local.flow_log_group_id
  flow_logs_retention_days   = var.flow_logs_retention_days

  freeform_tags = merge(var.freeform_tags, { role = "k8s-pods" })
}

module "subnet_lb" {
  source = "./modules/subnet"

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id

  name       = "${var.prefix}-lb"
  cidr_block = local.cidr_lb
  dns_label  = "lb"
  is_public  = true

  route_rules   = local.route_public
  ingress_rules = local.lb_ingress
  egress_rules  = local.lb_egress

  # The root owns the one shared log group, so every call turns the module's
  # own off. This is what makes the plan show 1 log group and not 5.
  flow_logs_enabled          = var.enable_flow_logs
  create_flow_logs_log_group = false
  flow_logs_log_group_id     = local.flow_log_group_id
  flow_logs_retention_days   = var.flow_logs_retention_days

  freeform_tags = merge(var.freeform_tags, { role = "service-load-balancers" })
}
