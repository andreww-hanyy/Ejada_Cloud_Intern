# main.tf — look up dependencies, then create the compute instance

# 1) Read the existing subnet so we can reuse its compartment automatically
data "oci_core_subnet" "lab" {
  subnet_id = var.subnet_ocid
}

locals {
  # The instance is created in the same compartment as the subnet
  compartment_ocid = data.oci_core_subnet.lab.compartment_id
}

# 2) Pick an availability domain in this compartment
data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_ocid
}

# 3) Find the latest Oracle Linux 9 image compatible with the chosen shape
data "oci_core_images" "ol9" {
  compartment_id           = local.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# 4) Create the Linux compute instance in the existing public subnet
resource "oci_core_instance" "lab2" {
  compartment_id      = local.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.instance_name
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ol9.images[0].id
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}
