# Lab 2 — Provision an OCI Compute Instance with Terraform

**Egypt Summer Internship Program 2026 — Cloud Build Track (OCI & Terraform)**
**Week 1 — Terraform Basics**

| | |
|---|---|
| **Intern** | Andrew Hany |
| **Compartment** | `intern-04-andrew-hany-cmp` |
| **Region** | `me-jeddah-1` — Saudi Arabia West (Jeddah) |
| **Tenancy** | `ociejada` |
| **Date** | 7 August 2026 |

---

## 1. Objective

Reproduce the compute instance from Lab 1 as **Infrastructure as Code** using Terraform. Per the Week 1 brief, the network (VCN, public subnet) is reused from the Lab 1 Console build — this lab focuses on **installing Terraform, configuring OCI access, and writing Terraform code that creates a compute instance.**

Scope:
- Install Terraform
- Configure API-key access to OCI
- Write Terraform code that provisions an OCI compute instance into the existing public subnet
- Verify by SSH, then tear down with a single command

---

## 2. Project structure

```
Lab 2/
├── provider.tf        # OCI provider + authentication
├── variables.tf       # input variable declarations
├── terraform.tfvars   # actual values (git-ignored — holds identifiers)
├── main.tf            # data lookups + the compute instance resource
├── outputs.tf         # public IP and other outputs
└── .gitignore         # excludes keys, tfvars, and state
```

---

## 3. Step 1 — Install Terraform

Installed the Terraform CLI on Windows with a single command:

```powershell
winget install --id Hashicorp.Terraform -e
```

After reopening the shell, verified the install: **`Terraform v1.15.8`**.

---

## 4. Step 2 — Configure OCI access (API key)

Terraform authenticates to OCI with an **API signing key**, not a password. Generated one under **Profile → User settings → Tokens and keys → Add API key → Generate API key pair**, downloaded the private/public keys, and copied the configuration preview (user OCID, fingerprint, tenancy OCID, region):

![OCI API key configuration file preview](screenshots/01-api-key-config.png)

Moved the private key to a dedicated folder outside the repo (so it is never committed), as `C:\Users\HP\.oci\oci_api_key.pem`:

![Private key placed in the .oci folder](screenshots/02-oci-key-placed.png)

These values feed the provider block. `terraform.tfvars` holds the identifiers and the key **path** (the key file itself stays in `.oci` and is git-ignored).

---

## 5. Step 3 — The Terraform code

### `provider.tf`
```hcl
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
```

### `main.tf` (the important part)
```hcl
# Reuse the existing subnet and derive the compartment from it
data "oci_core_subnet" "lab" {
  subnet_id = var.subnet_ocid
}

locals {
  compartment_ocid = data.oci_core_subnet.lab.compartment_id
}

# Look up an availability domain and the latest Oracle Linux 9 image
data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_ocid
}

data "oci_core_images" "ol9" {
  compartment_id           = local.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Create the compute instance in the existing public subnet
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
```

**Design note:** the only value supplied by hand is the **subnet OCID**. Terraform derives the compartment from the subnet, and uses *data sources* to resolve the availability domain and the newest Oracle Linux 9 image automatically. This keeps the code portable and is a good demonstration of Terraform data sources.

---

## 6. Step 4 — Initialize

```powershell
terraform init
```

Downloads the OCI provider (v8.26.0) and prepares the working directory:

![terraform init succeeded](screenshots/03-terraform-init.png)

---

## 7. Step 5 — Plan (dry run)

```powershell
terraform plan
```

Authenticates, runs the lookups, and previews exactly one resource to create — no changes are made yet:

![terraform plan: 1 to add](screenshots/04-terraform-plan.png)

The plan confirms: availability domain `oXVt:ME-JEDDAH-1-AD-1`, image `Oracle-Linux-9.8-2026.07.20-1`, shape `VM.Standard.E5.Flex` (1 OCPU / 12 GB), public IP enabled — `Plan: 1 to add`.

---

## 8. Step 6 — Apply

```powershell
terraform apply    # answer: yes
```

Terraform creates the instance in **27 seconds** and prints the outputs, including the public IP:

![terraform apply complete](screenshots/05-terraform-apply.png)

```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:
image_used         = "Oracle-Linux-9.8-2026.07.20-1"
instance_name      = "lab2-instance"
instance_public_ip = "207.127.101.24"
instance_state     = "RUNNING"
```

---

## 9. Step 7 — Verify (SSH)

Connected to the Terraform-built instance using the same key pair from Lab 1:

```powershell
ssh -i $env:USERPROFILE\.ssh\ssh-key-2026-08-05.key opc@207.127.101.24
```

![SSH into the Terraform-built instance](screenshots/06-ssh-verify.png)

Landing at `[opc@lab2-instance ~]$` confirms the instance is real and reachable.

---

## 10. Cleanup

Because this is a shared tenancy, the instance is torn down after review with a single command — no manual, ordered deletes:

```powershell
terraform destroy    # answer: yes
```

This removes **only** the `lab2-instance` Terraform created; the Console-built network is read-only in this configuration and is left untouched.

---

## 11. Lab 1 vs Lab 2 — why IaC

| | Lab 1 (Console) | Lab 2 (Terraform) |
|---|---|---|
| Create instance | ~15 min of clicking | `terraform apply` — 27 s |
| Repeatable | No — manual each time | Yes — identical every run |
| Documented | Screenshots after the fact | The code *is* the documentation |
| Teardown | Delete each resource in order | `terraform destroy` — one command |

Doing Lab 1 by hand first made every block in this code recognizable — the value of Infrastructure as Code is that the environment is now versionable, repeatable, and disposable.
