###############################################################################
# locals.tf - derived values. Nothing below is typed twice or hardcoded.
###############################################################################

locals {
  # Fall back to the root compartment if none was supplied.
  compartment_id = coalesce(var.compartment_ocid, var.tenancy_ocid)

  # Every resource name is built from this prefix, e.g. "ejada-w2-dev-vcn".
  name_prefix = "${var.project_name}-${var.environment}"

  # DNS labels must be alphanumeric only, max 15 chars.
  vcn_dns_label = substr(replace(local.name_prefix, "-", ""), 0, min(15, length(replace(local.name_prefix, "-", ""))))

  # Subnets are carved out of the VCN CIDR so changing vcn_cidr changes everything.
  public_subnet_cidr  = cidrsubnet(var.vcn_cidr, var.subnet_newbits, var.public_subnet_index)
  private_subnet_cidr = cidrsubnet(var.vcn_cidr, var.subnet_newbits, var.private_subnet_index)

  # Single availability domain used by the instance, the file system and the mount target.
  availability_domain = data.oci_identity_availability_domains.this.availability_domains[var.availability_domain_index].name

  # Private IP of the mount target, resolved after creation - never hardcoded.
  mount_target_ip = data.oci_core_private_ip.mount_target.ip_address

  # NFS needs these ports open between the instance and the mount target.
  nfs_tcp_ports = [111, 2048, 2049, 2050]
  nfs_udp_ports = [111, 2048]

  anywhere = "0.0.0.0/0"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Lab         = "Week2-Lab2"
    },
    var.freeform_tags
  )
}
