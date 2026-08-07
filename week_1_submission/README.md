# Week 1 Submission — Cloud Build Track (OCI & Terraform)

**Egypt Summer Internship Program 2026**
**Intern:** Andrew Hany · **Compartment:** `intern-04-andrew-hany-cmp` · **Region:** `me-jeddah-1` (Jeddah)

This folder contains the Week 1 deliverables for the "Build Your First OCI Environment" assignment.

## Contents

### `lab1/` — OCI Compute Deployment (Console)
Built a VCN, public subnet, and Linux compute instance in the OCI Console, then attached a block volume and file storage.
- `README.md` — full walkthrough with architecture diagram and screenshots
- `Lab1_Documentation.docx` — the same, as a Word document
- `screenshots/` — step-by-step evidence

### `lab2/` — Terraform Basics
Reproduced the compute instance as Infrastructure as Code with Terraform (network reused from Lab 1, per the Week 1 brief).
- `provider.tf`, `variables.tf`, `main.tf`, `outputs.tf` — the Terraform configuration
- `terraform.tfvars.example` — template for the required inputs (real `terraform.tfvars` is git-ignored)
- `.gitignore` — excludes secrets, state, and provider binaries
- `README.md` — walkthrough (install → auth → code → apply → verify) with screenshots
- `Lab2_Documentation.docx` — the same, as a Word document
- `screenshots/` — step-by-step evidence

## Notes
- No secrets are included: private keys, the real `terraform.tfvars`, and Terraform state are intentionally excluded.
- Lab 2 scope follows the mentor's clarification (Terraform for the compute instance; network built in the Console).
