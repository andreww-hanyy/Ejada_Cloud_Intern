# Week 2 — Lab 2: Load-Balanced Private Application with OCI File Storage

**Ejada Egypt Summer Internship Program 2026 · Cloud Build Track**
Andrew Hany · Compartment `intern-04-andrew-hany-cmp` · Region `me-jeddah-1`

A public Application Load Balancer in a public subnet fronts a private compute instance that has **no public IP address**. The instance runs Apache, and every file it serves lives on an OCI File Storage share mounted over NFS at the Apache document root.

Built twice: once by hand through the OCI Console and CLI (Step 1), then entirely in Terraform (Step 2).

---

## What's in this folder

| Path | What it is |
|---|---|
| `Week2_Lab2_Technical_Report.docx` / `.pdf` | **Main deliverable.** Full technical report — configuration of every resource, design reasoning, issues encountered, verification checklist. |
| `arch.drawio.png` | Architecture diagram (also embedded in the report) |
| `architecture.drawio` | Editable diagram source |
| `terraform/` | Step 2 — the complete Terraform implementation |
| `screenshots/` | OCI Console evidence referenced by the report |
| `cloud-init-console.sh` | Bootstrap script used to install the application |
| `LAB_LOG.md` | Working build log kept during Step 1 — supporting detail behind the report |

---

## Architecture

```
Internet client
   → Application Load Balancer   (public subnet  10.0.1.0/24, public IP, :80)
   → Compute instance            (private subnet 10.0.2.0/24, NO public IP, :80)
   → Apache serves from /var/www/html
   → which is an NFS mount of the File Storage export /app
```

| Layer | Resource | CIDR / detail |
|---|---|---|
| Network | `ejada-w2-dev-vcn` | `10.0.0.0/16` |
| Public tier | `ejada-w2-dev-subnet-public` | `10.0.1.0/24` — load balancer |
| Private tier | `ejada-w2-dev-subnet-private` | `10.0.2.0/24` — instance + FSS mount target |
| Egress | Internet / NAT / Service gateways | public two-way, private outbound-only, OCI services over the backbone |
| Compute | Oracle Linux 9, `VM.Standard.E5.Flex` | 1 OCPU / 12 GB, no public IP |
| Storage | File Storage export `/app` | mount target `10.0.2.177`, mounted at `/var/www/html` |
| Entry point | Flexible load balancer, 10 Mbps | HTTP :80, health check `GET /` |

---

## Running the Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then fill in your own values
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

`terraform.tfvars` is deliberately **not** included — it holds tenancy identifiers and an SSH public key. Use `terraform.tfvars.example` as the template.

### File layout

| File | Contents |
|---|---|
| `provider.tf` | Provider and version constraints |
| `variables.tf` | Every input, typed, described, several validated |
| `locals.tf` | Derived values — CIDRs, names, NFS port lists, tags |
| `data.tf` | Lookups: availability domains, image, OSN service, mount target IP |
| `network.tf` | VCN, 3 gateways, 2 route tables, 2 security lists, 2 subnets |
| `security.tf` | 3 NSGs and their rules |
| `storage.tf` | File system, mount target, export |
| `compute.tf` | Private instance + cloud-init |
| `cloud-init.sh.tftpl` | Bootstrap template rendered by `templatefile()` |
| `loadbalancer.tf` | Load balancer, backend set, backend, listener |
| `bastion.tf` | OCI Bastion — **disabled by default**, see note below |
| `outputs.tf` | Application URL, IPs, mount command, bastion command |

### Code-quality notes

- **No hardcoded values.** Every OCID, CIDR, port, shape and name comes from a variable or is derived in `locals.tf`. Subnet CIDRs use `cidrsubnet()` on the VCN CIDR; the mount target IP is resolved through a data source; the OS image is looked up rather than pinned by OCID.
- **Variables and locals throughout** — 30+ typed variables with descriptions, several with `validation` blocks.
- **Split across files by concern**, not one `main.tf`.
- **`.tfvars` for values**, with a committed `.example`.
- **Data sources, dependencies and lifecycle rules** — implicit dependencies via references plus an explicit `depends_on` so the instance never boots before its NFS export exists, and `ignore_changes` on the instance image.

---

## Known constraints

**OCI Bastion is disabled by default.** The lab account holds `read` but not `manage` on `bastion-family`, so creating a bastion returns `NotAuthorizedOrNotFound`. `bastion.tf` is therefore gated behind `create_bastion` (default `false`) so that `terraform apply` succeeds without the grant. Set it to `true` once this policy exists:

```
allow group <interns> to manage bastion-family in compartment intern-04-andrew-hany-cmp
```

Because neither Bastion nor the Run Command agent plugin was available, the application was installed through **cloud-init at first boot** rather than an interactive session. Full detail is in Section 9 of the report.

---

## Gotchas worth knowing

| Symptom | Cause |
|---|---|
| HTTP 403 from Apache | SELinux blocks reading an NFS mount — needs `setsebool -P httpd_use_nfs 1` |
| LB backend stuck Critical, instance looks fine | Port 80 closed in firewalld on a fresh Oracle Linux 9 image |
| `mount` hangs instead of erroring | An NFS port missing — needs TCP 111, 2048–2050 and UDP 111, 2048 |
| `chown` fails on the NFS mount | Identity squash enabled — set anonymous access to "Not allowed" |
| Mount target won't fit in a subnet | It consumes three IP addresses; never use a /30 or smaller |
