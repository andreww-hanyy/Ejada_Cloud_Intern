# Week 3 — OKE with reusable Terraform modules

Ejada Summer Internship 2026 · Cloud Build track
**Andrew Hany** · compartment `intern-04-andrew-hany-cmp` · region `me-jeddah-1`

---

## What this is

An OKE cluster with VCN-native pod networking and a managed worker node pool,
running a small NGINX application that serves its content from an **external
OCI Block Volume** and is exposed through an **OCI Load Balancer** — all built
from two generic, reusable Terraform modules.

The brief's emphasis was explicit: *"the goal is not only to make it work, but
to build it in a clean, reusable, and configurable Terraform structure."* So the
module design is the primary deliverable and the running cluster is the proof.

## Layout

```
week_3_submission/
├── README.md                      you are here
├── run-lab.sh                     runs the lab and captures the evidence
├── Week3_Technical_Report.docx    the report (.pdf alongside it)
├── docs/
│   ├── TERRAFORM_MODULES_NOTES.md dynamic blocks · conditionals · reusability
│   ├── ARCHITECTURE.md            address plan, traffic paths, design decisions
│   ├── RUNBOOK.md                 every command, in order
│   └── architecture.svg/.png/.drawio
├── terraform/
│   ├── modules/
│   │   ├── subnet/                subnet + route table + security list + flow log
│   │   └── oke/                   cluster + node pools + add-ons
│   ├── network.tf                 VCN, gateways, shared log group
│   ├── locals.tf                  all security and routing rules
│   ├── subnets.tf                 4 × the subnet module
│   ├── oke.tf                     1 × the OKE module
│   ├── variables.tf outputs.tf provider.tf
│   └── terraform.tfvars.example
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 10-pvc.yaml                block volume via the oci-bv storage class
│   ├── 20-deployment.yaml         NGINX + init container that seeds the volume
│   └── 30-service-lb.yaml         Service type=LoadBalancer
├── screenshots/console/           21 OCI Console captures
└── evidence/                      42 captured command outputs
```

## The modules

### `modules/subnet`

The four resources that always travel together, as one unit:

| # | Resource | Optional? |
|---|---|---|
| 1 | `oci_core_subnet` | always |
| 2 | `oci_core_route_table` | `create_route_table` |
| 3 | `oci_core_security_list` | `create_security_list` |
| 4 | `oci_logging_log` (VCN flow logs) | `flow_logs_enabled` |

Called **four times** in this stack, for four subnets that differ in size
(`/29` to `/19`), posture (public and private), routing (IGW vs. NAT + service
gateway) and rule count (3 to 13 rules) — with **no branching inside the module
written for any particular one of them**.

### `modules/oke`

Cluster, node pools and add-ons. Supports both `OCI_VCN_IP_NATIVE` and
`FLANNEL_OVERLAY`, public or private API endpoints, and any number of node
pools via `for_each` over a map. The Kubernetes version and the node image are
**discovered from the region**, not hardcoded — including selecting an
`aarch64` image automatically when the shape is Ampere.

## Techniques used

| Technique | Where |
|---|---|
| `dynamic` blocks | route rules; ingress/egress rules; node pool placement configs; node labels |
| Nested `dynamic` (3 deep) | `ingress_security_rules` → `tcp_options` → `source_port_range` |
| `for_each = cond ? [x] : []` | making a *single* block conditional (`node_shape_config`, pod network details) |
| `count = cond ? 1 : 0` | optional route table, security list, log group |
| `for_each` over a map | N node pools, N add-ons, from one resource block |
| `optional()` in object types | heterogeneous rule lists that stay readable |
| `try` / `coalesce` / `compact` | resolving "caller's value, else the one we made, else none" |
| `validation` | CIDR format, protocol numbers, retention values, pool size |
| `precondition` | VCN-native requires pod subnets; no image found for shape |
| Data-source defaults | newest Kubernetes version; matching OKE node image per architecture |

`docs/TERRAFORM_MODULES_NOTES.md` walks through each of these with the actual
code.

## Quick start

Fill in your OCIDs, then let the runner drive it:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # edit it
./run-lab.sh preflight     # tooling, IAM reachability, shape availability
./run-lab.sh plan          # init, fmt, validate, plan + assertions
./run-lab.sh apply
./run-lab.sh kubeconfig
./run-lab.sh deploy
./run-lab.sh verify
./run-lab.sh persistence
```

`run-lab.sh` saves the full output of every command to `evidence/<run>/` and
pauses at the exact moments a screenshot is worth taking, naming the file to
use. `NO_PAUSE=1` skips those stops; `RUN_ID=<name>` keeps several stages'
evidence in one folder. It is plain POSIX shell, so it also runs unchanged in
**OCI Cloud Shell**, where `oci` and `kubectl` are already installed and
authenticated.

Two checks in it are worth knowing about. After planning it parses
`terraform show -json` and asserts the resource counts — including that there
is exactly **one** log group, not five, which is the tell that the shared
`flow_logs_log_group_id` wiring still works. After deploying it reads the pod
IP back and confirms it falls inside the pod subnet, since an address in
`10.244.0.0/16` would mean flannel rather than VCN-native networking.

Doing it by hand instead, or diagnosing something that went wrong:
`docs/RUNBOOK.md` has every command and a troubleshooting table.

## Teardown

`terraform destroy` alone is **not enough**. The load balancer and the block
volume were created by Kubernetes, so Terraform doesn't track them and the VCN
delete will fail while the LB still holds a VNIC in the subnet:

```powershell
kubectl delete -f k8s/     # wait for the LB and volume to disappear
cd terraform
terraform destroy
```

## Security notes

- `terraform.tfvars`, `*.pem`, `*.key` and kubeconfig files are gitignored.
- The kubeconfig is **not** a Terraform output — that would put a cluster
  credential in plain text in `terraform.tfstate`. The module outputs the
  `oci ce cluster create-kubeconfig` command instead.
- `kubectl_source_cidr` defaults to `0.0.0.0/0` for lab convenience. It is the
  first thing to narrow in any real deployment, and it is a variable
  specifically so that narrowing it is a one-line change.
- Worker nodes have no public IPs; the load balancer is the only ingress path.

## Requirements

- Terraform ≥ 1.3 (`optional()` in object type constraints)
- `oracle/oci` provider ≥ 5.0 — pinned to 8.27.0 in `.terraform.lock.hcl`
- OCI CLI, `kubectl`

> On Windows, install the OCI CLI into a **short** path
> (`python -m venv C:\oci` then `C:\oci\Scripts\python.exe -m pip install oci-cli`).
> Oracle's `install.ps1` targets `%USERPROFILE%\lib\oracle-cli`, and the longest
> file in the `oci_cli` wheel has a 229-character relative path, which takes the
> full path past `MAX_PATH` and fails the install at 23/24 packages.
- Compartment permissions: `cluster-family`, `virtual-network-family`,
  `instance-family`, `volume-family`, `load-balancers`, `log-groups`,
  `log-content`
