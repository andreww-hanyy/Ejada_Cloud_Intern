###############################################################################
# loadbalancer.tf - public Application Load Balancer in the public subnet
###############################################################################

resource "oci_load_balancer_load_balancer" "this" {
  compartment_id             = local.compartment_id
  display_name               = "${local.name_prefix}-lb"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.public.id]
  network_security_group_ids = [oci_core_network_security_group.lb.id]
  is_private                 = false
  freeform_tags              = local.common_tags

  shape_details {
    minimum_bandwidth_in_mbps = var.lb_min_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.lb_max_bandwidth_mbps
  }
}

resource "oci_load_balancer_backend_set" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "${replace(local.name_prefix, "-", "_")}_backendset"
  policy           = var.lb_policy

  health_checker {
    protocol          = "HTTP"
    url_path          = var.app_health_check_path
    port              = var.app_port
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  backendset_name  = oci_load_balancer_backend_set.app.name
  ip_address       = oci_core_instance.app.private_ip
  port             = var.app_port
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "${replace(local.name_prefix, "-", "_")}_listener_http"
  default_backend_set_name = oci_load_balancer_backend_set.app.name
  port                     = var.app_port
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 60
  }
}
