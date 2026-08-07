# variables.tf — inputs for the configuration

# --- OCI API authentication ---
variable "tenancy_ocid" {
  type        = string
  description = "OCID of the tenancy"
}

variable "user_ocid" {
  type        = string
  description = "OCID of the API user"
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint of the API signing key"
}

variable "private_key_path" {
  type        = string
  description = "Path to the API private key (.pem) on this machine"
}

variable "region" {
  type        = string
  description = "OCI region identifier"
  default     = "me-jeddah-1"
}

# --- Instance placement ---
variable "subnet_ocid" {
  type        = string
  description = "OCID of the existing public subnet (created in the Console in Lab 1)"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key placed on the instance for the opc user"
}

# --- Instance sizing (sensible defaults) ---
variable "instance_name" {
  type    = string
  default = "lab2-instance"
}

variable "instance_shape" {
  type    = string
  default = "VM.Standard.E5.Flex"
}

variable "instance_ocpus" {
  type    = number
  default = 1
}

variable "instance_memory_gbs" {
  type    = number
  default = 12
}
