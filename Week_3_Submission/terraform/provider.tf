terraform {
  required_version = ">= 1.3.0"

  required_providers {
    oci = {
      source = "oracle/oci"
      # Pinned to a major version at the ROOT, so a rebuild of this commit
      # months from now gets the same provider. The modules deliberately use a
      # looser ">= 5.0.0" instead: a module should state its minimum, and let
      # whoever consumes it decide the exact version.
      version = "~> 8.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
