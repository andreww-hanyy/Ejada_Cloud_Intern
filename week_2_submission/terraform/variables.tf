###############################################################################
# variables.tf - every input the configuration accepts
###############################################################################

# ----------------------------------------------------------------------------
# Authentication / tenancy
# ----------------------------------------------------------------------------
variable "tenancy_ocid" {
  type        = string
  description = "OCID of the tenancy."
}

variable "user_ocid" {
  type        = string
  description = "OCID of the API user."
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the API signing key."
}

variable "private_key_path" {
  type        = string
  description = "Path to the API private key (.pem) on the machine running Terraform."
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. me-jeddah-1."
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of the compartment that will hold every resource. Leave empty to use the tenancy (root) compartment."
  default     = ""
}

# ----------------------------------------------------------------------------
# Naming
# ----------------------------------------------------------------------------
variable "project_name" {
  type        = string
  description = "Short project identifier used as a prefix on every resource name."
  default     = "ejada-w2"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 characters, lowercase letters, digits or hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment tag/suffix (dev, test, prod)."
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, prod."
  }
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------
variable "vcn_cidr" {
  type        = string
  description = "CIDR block for the VCN. Subnets are carved out of this automatically."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vcn_cidr, 0))
    error_message = "vcn_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_newbits" {
  type        = number
  description = "Extra bits added to the VCN prefix when carving subnets. 8 turns a /16 into /24s."
  default     = 8
}

variable "public_subnet_index" {
  type        = number
  description = "Index of the public subnet inside the VCN CIDR."
  default     = 1
}

variable "private_subnet_index" {
  type        = number
  description = "Index of the private subnet inside the VCN CIDR."
  default     = 2
}

variable "availability_domain_index" {
  type        = number
  description = "Which availability domain to use (0 = first). Most single-AD regions only have index 0."
  default     = 0
}

# ----------------------------------------------------------------------------
# Access control
# ----------------------------------------------------------------------------
variable "allowed_http_cidr" {
  type        = string
  description = "CIDR allowed to reach the load balancer on the application port."
  default     = "0.0.0.0/0"
}

variable "bastion_client_cidr_allow_list" {
  type        = list(string)
  description = "CIDRs allowed to open sessions on the OCI Bastion. Narrow this to your own public IP/32 for real work."
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed for the opc user on the private instance."
}

# ----------------------------------------------------------------------------
# Application
# ----------------------------------------------------------------------------
variable "app_port" {
  type        = number
  description = "TCP port the application listens on inside the private instance."
  default     = 80
}

variable "app_health_check_path" {
  type        = string
  description = "URL path the load balancer health checker requests on the backend."
  default     = "/"
}

variable "app_document_root" {
  type        = string
  description = "Directory on the instance where the File Storage export is mounted and served from."
  default     = "/var/www/html"
}

# ----------------------------------------------------------------------------
# Compute
# ----------------------------------------------------------------------------
variable "instance_shape" {
  type        = string
  description = "Compute shape for the private application instance."
  default     = "VM.Standard.E5.Flex"
}

variable "instance_ocpus" {
  type        = number
  description = "OCPU count for the flexible shape."
  default     = 1
}

variable "instance_memory_gbs" {
  type        = number
  description = "Memory in GB for the flexible shape."
  default     = 12
}

variable "instance_os" {
  type        = string
  description = "Operating system used to select the platform image."
  default     = "Oracle Linux"
}

variable "instance_os_version" {
  type        = string
  description = "Operating system version used to select the platform image."
  default     = "9"
}

# ----------------------------------------------------------------------------
# File Storage
# ----------------------------------------------------------------------------
variable "fss_export_path" {
  type        = string
  description = "Export path published by the File Storage mount target."
  default     = "/app"
}

# ----------------------------------------------------------------------------
# Load Balancer
# ----------------------------------------------------------------------------
variable "lb_min_bandwidth_mbps" {
  type        = number
  description = "Guaranteed bandwidth for the flexible load balancer shape."
  default     = 10
}

variable "lb_max_bandwidth_mbps" {
  type        = number
  description = "Maximum bandwidth for the flexible load balancer shape."
  default     = 10
}

variable "lb_policy" {
  type        = string
  description = "Load balancing policy for the backend set."
  default     = "ROUND_ROBIN"
}

# ----------------------------------------------------------------------------
# Optional extras
# ----------------------------------------------------------------------------
variable "create_bastion" {
  type        = bool
  description = "Create the OCI Bastion service. Requires `manage bastion-family` in the target compartment; disabled by default because the lab account holds only `read` (see report Section 9, Issue 4)."
  default     = false
}

variable "create_bastion_session" {
  type        = bool
  description = "Create a managed-SSH bastion session with Terraform. Sessions expire, which causes plan drift - the console/CLI is usually the better place to create them."
  default     = false
}

variable "bastion_max_session_ttl_seconds" {
  type        = number
  description = "Maximum lifetime of a bastion session, in seconds (max 10800)."
  default     = 10800
}

variable "freeform_tags" {
  type        = map(string)
  description = "Extra freeform tags merged onto every resource."
  default     = {}
}
