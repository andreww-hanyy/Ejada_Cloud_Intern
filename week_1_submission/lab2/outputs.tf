# outputs.tf — values Terraform prints after apply

output "instance_name" {
  value = oci_core_instance.lab2.display_name
}

output "instance_public_ip" {
  description = "SSH to this: ssh -i <private-key> opc@<this-ip>"
  value       = oci_core_instance.lab2.public_ip
}

output "instance_state" {
  value = oci_core_instance.lab2.state
}

output "image_used" {
  value = data.oci_core_images.ol9.images[0].display_name
}
