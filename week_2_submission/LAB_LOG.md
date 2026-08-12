# OCI Cloud Lab — Technical Deployment Report (DRAFT / working log)

**Week 2 — Lab 2: Load-Balanced Private Application with File Storage**
Ejada Egypt Summer Internship Program 2026 · Cloud Build Track

> This file is filled in step by step as the lab is built. When Step 1 is complete it becomes the source for the final PDF report. Sections marked _Pending_ have not been built yet.

| Field | Detail |
|---|---|
| Lab | Week 2 – Lab 2 |
| Virtual Cloud Network | `ejada-w2-dev-vcn` (10.0.0.0/16) |
| Region | me-jeddah-1 |
| Compartment | intern-04-andrew-hany-cmp |
| Deployment Date | August 12, 2026 (UTC) |
| Document Type | Technical Deployment & Verification Report |
| Provisioning Method | Step 1: OCI Console (manual) · Step 2: Terraform |

---

## 2. Project Overview & Objectives

_To be written once the build is complete._

**Objectives**

- Design a VCN with a public tier for internet-facing traffic and a private tier for the workload.
- Configure Internet, NAT and Service gateways with matching route tables so the private subnet can reach out but never be reached in.
- Control traffic with Network Security Groups that reference each other, rather than broad subnet CIDRs.
- Provision an OCI File Storage file system and mount target, and mount the export on the instance over NFS.
- Launch an Oracle Linux compute instance in the private subnet with **no public IP**, running Apache served from the File Storage mount.
- Publish the application through a public Application Load Balancer in the public subnet.
- Establish administrative access through the OCI Bastion service.
- Verify end to end, then rebuild the identical environment 100% in Terraform.

---

## 3. Prerequisites

| Item | Value / Status |
|---|---|
| OCI Tenancy | ociejada (identity domain: Ejada-interim-program) |
| Region | me-jeddah-1 |
| Working Compartment | intern-04-andrew-hany-cmp |
| Console Access | OCI Web Console (browser-based) |
| SSH Client | Windows PowerShell (OpenSSH client) |
| SSH Key Pair | Reused from Week 1 — `ssh-key-2026-08-05` |
| Target OS Image | _pending — record exact image name from the instance page_ |
| Provisioning Method | Step 1: Console only · Step 2: Terraform |

### Address plan

| Item | CIDR | Purpose |
|---|---|---|
| VCN | `10.0.0.0/16` | Whole network |
| Public subnet | `10.0.1.0/24` | Application Load Balancer |
| Private subnet | `10.0.2.0/24` | Compute instance + File Storage mount target |

---

## 4. VCN Configuration

The network foundation for the lab is a single Virtual Cloud Network, `ejada-w2-dev-vcn`, created in the `intern-04-andrew-hany-cmp` compartment in the `me-jeddah-1` (Saudi Arabia West — Jeddah) region. It was allocated the IPv4 CIDR block `10.0.0.0/16`, which is deliberately larger than this lab needs so that both subnet tiers — and any later ones — can be carved out of a single contiguous range.

The VCN was created with the plain **Create VCN** action rather than the VCN Wizard. The wizard would have auto-provisioned its own subnets, gateways and route rules; building each component explicitly makes the public/private split visible in the configuration and keeps the manual build aligned one-to-one with the Terraform in Step 2.

![Figure 1 — VCN details](../screenshots/console/fig01-vcn-details.png)

*Figure 1. `ejada-w2-dev-vcn` details page — CIDR 10.0.0.0/16, compartment intern-04-andrew-hany-cmp, region me-jeddah-1, state Available, and the auto-created Default Route Table and DNS Resolver.*

**VCN Summary**

| Attribute | Value |
|---|---|
| Name | `ejada-w2-dev-vcn` |
| Compartment | `intern-04-andrew-hany-cmp` |
| Region | me-jeddah-1 (Saudi Arabia West — Jeddah) |
| State | Available |
| IPv4 CIDR Block | `10.0.0.0/16` |
| IPv6 Prefix | Not configured |
| DNS Domain Name | `ejadaw2dev.oraclevcn.com` |
| Default Route Table | Default Route Table for ejada-w2-dev-vcn (left unused) |
| OCID | `ocid1.vcn.oc1.me-jeddah-1.amaaaaaavjakbniamrjvpoavw6ikbuj5miewklpaovhjuqs3k746oivkhq2a` |
| Created | Aug 12, 2026, 16:19:11 UTC |

> **Design note.** The VCN ships with a Default Route Table, Default Security List and Default DHCP Options. All three are left empty and unattached for the rest of this lab; purpose-built route tables and security lists are created in Sections 6 and 7 and attached to the subnets explicitly. Using the defaults would have worked, but it would hide the distinction between the public and private tiers — the exact distinction this lab is meant to demonstrate.

---

## 5. Gateways

Three gateways were attached to `ejada-w2-dev-vcn`, one for each distinct traffic pattern the design requires. All three reached **Available** state on creation.

**Gateway Summary**

| Gateway | Name | State | Detail | Created (UTC) |
|---|---|---|---|---|
| Internet Gateway | `ejada-w2-dev-igw` | Available | — | Aug 12, 2026, 16:35:32 |
| NAT Gateway | `ejada-w2-dev-natgw` | Available | Public IP `80.225.77.255` (ephemeral) | Aug 12, 2026, 16:35:52 |
| Service Gateway | `ejada-w2-dev-sgw` | Available | All JED Services In Oracle Services Network | Aug 12, 2026, 16:36:23 |

### 5.1 Internet Gateway

The Internet Gateway provides **bidirectional** internet connectivity, and is used only by the public subnet. It is what allows the load balancer to be assigned a public IP address and receive requests from clients on the internet.

![Figure 2 — Internet Gateway](../screenshots/console/fig02a-internet-gateway.png)

*Figure 2. Internet Gateways list for compartment intern-04-andrew-hany-cmp — `ejada-w2-dev-igw` in Available state.*

### 5.2 NAT Gateway

The NAT Gateway provides **outbound-only** internet connectivity for the private subnet. Instances behind it can initiate connections outward — which is how the application instance installs `httpd` and `nfs-utils` from the Oracle Linux repositories — but no host on the internet can initiate a connection inward. This asymmetry is the practical definition of a private subnet in OCI.

Without this gateway the private instance would have no path to the package repositories and the application could not be installed at all, so it is a hard requirement of this design rather than an optional extra.

The gateway was created with an **ephemeral** public IP. A reserved public IP would persist across recreation but carries a cost and provides no benefit for a short-lived lab.

![Figure 3 — NAT Gateway](../screenshots/console/fig02b-nat-gateway.png)

*Figure 3. NAT Gateways list — `ejada-w2-dev-natgw` in Available state with ephemeral public IP 80.225.77.255.*

### 5.3 Service Gateway

The Service Gateway allows the private subnet to reach OCI services — Object Storage and others in the Oracle Services Network — across Oracle's internal backbone rather than through the NAT Gateway and the public internet.

It is not strictly required for this lab, since nothing in the application depends on Object Storage. It is included because it is standard practice in an enterprise private-subnet design: keeping service traffic off the NAT path reduces both latency and NAT data-processing charges at scale, and the traffic never traverses the public internet.

![Figure 4 — Service Gateway](../screenshots/console/fig02c-service-gateway.png)

*Figure 4. Service Gateways list — `ejada-w2-dev-sgw` in Available state, targeting All JED Services In Oracle Services Network.*

> **Note on the empty Route Table column.** All three gateways show `—` under Route Table. A gateway on its own only creates the *capability* to route traffic; it carries none until a route rule names it as a target. Those rules are added in Section 6, and traffic begins to flow only at that point.

---

## 6. Route Tables

Two purpose-built route tables were created, one per subnet tier. The VCN's Default Route Table was deliberately left with **zero rules** and is not attached to either subnet — the public/private distinction in this design is expressed entirely through which route table a subnet uses, so leaving the default empty makes that distinction unambiguous.

![Figure 5 — Route tables](../screenshots/console/fig05-route-tables-list.png)

*Figure 5. Route Tables in compartment intern-04-andrew-hany-cmp — the private table with 2 rules, the public table with 1, and the unused Default Route Table with 0.*

**Route Table Summary**

| Route Table | Rules | State | Created (UTC) |
|---|---|---|---|
| `ejada-w2-dev-rt-private` | 2 | Available | Aug 12, 2026, 16:40:08 |
| `ejada-w2-dev-rt-public` | 1 | Available | Aug 12, 2026, 16:39:01 |
| Default Route Table for ejada-w2-dev-vcn | 0 | Available | Aug 12, 2026, 16:19:11 |

### 6.1 Public route table

A single default route sends all non-local traffic to the Internet Gateway. Combined with a subnet marked as public, this is what makes the load balancer reachable from the internet.

![Figure 6 — Public route rules](../screenshots/console/fig07-rt-public-rules.png)

*Figure 6. `ejada-w2-dev-rt-public` Route Rules — destination 0.0.0.0/0, target type Internet Gateway, target ejada-w2-dev-igw, route type Static.*

| Destination | Target Type | Target | Route Type |
|---|---|---|---|
| `0.0.0.0/0` | Internet Gateway | `ejada-w2-dev-igw` | Static |

### 6.2 Private route table

Two rules, each serving a different destination class:

![Figure 7 — Private route rules](../screenshots/console/fig06-rt-private-rules.png)

*Figure 7. `ejada-w2-dev-rt-private` Route Rules — 0.0.0.0/0 via the NAT Gateway, and the Oracle Services Network service CIDR label via the Service Gateway.*

| Destination | Target Type | Target | Route Type |
|---|---|---|---|
| `0.0.0.0/0` | NAT Gateway | `ejada-w2-dev-natgw` | Static |
| All JED Services In Oracle Services Network | Service Gateway | `ejada-w2-dev-sgw` | Static |

This pair of rules is the clearest single expression of the design intent. The default route allows the instance to reach the internet **outbound only**, because a NAT Gateway has no mechanism for accepting inbound connections. The second rule is more specific than `0.0.0.0/0`, so OCI's longest-prefix-match routing selects it for any traffic bound for an OCI service, keeping that traffic on the Oracle backbone rather than sending it out through NAT.

> **Note.** The Service Gateway destination is not a CIDR typed by hand; it is a **service CIDR label** selected from a dropdown. Oracle maintains the underlying address ranges, so the rule keeps working if those ranges change.

> **Note on local traffic.** Neither table contains a rule for `10.0.0.0/16`. Routing between subnets inside a VCN is implicit and cannot be removed, so an intra-VCN rule would be redundant. This matters later: the load balancer in `10.0.1.0/24` reaches the instance in `10.0.2.0/24` without any route rule at all — that path is governed purely by security rules (Sections 7 and 8), not by routing.

### 6.3 Attachment status

Both tables exist but are not yet attached to anything, because the subnets have not been created. They are selected during subnet creation in Section 9, which is the point at which these rules begin to take effect.

---

## 7. Security Lists

Two purpose-built security lists were created and the VCN's Default Security List was left unattached. Both are deliberately **minimal**: they carry only an outbound allow rule and an ICMP path-MTU rule. Every application-level rule (HTTP, SSH, NFS) lives in a Network Security Group instead — see Section 8.

**Security List Summary**

| Security List | Applies to | Created (UTC) |
|---|---|---|
| `ejada-w2-dev-sl-public` | Public subnet | Aug 12, 2026, 16:46:52 |
| `ejada-w2-dev-sl-private` | Private subnet | Aug 12, 2026, 16:49:35 |
| Default Security List for ejada-w2-dev-vcn | *(unused)* | Aug 12, 2026, 16:19:11 |

`ejada-w2-dev-sl-public` OCID: `ocid1.securitylist.oc1.me-jeddah-1.aaaaaaaakur55me2k6m4sylvhdfrsc4elxdokji3sr25y5jkldpqnoaswjja`

### 7.1 Public security list

![Figure 8 — Public security list rules](../screenshots/console/fig08b-sl-public-rules.png)

*Figure 8. `ejada-w2-dev-sl-public` — ingress ICMP type 3 code 4 from 0.0.0.0/0; egress all protocols to 0.0.0.0/0.*

| Direction | Source / Destination | Protocol | Type & Code | Purpose |
|---|---|---|---|---|
| Ingress | `0.0.0.0/0` | ICMP | 3, 4 | Path MTU discovery |
| Egress | `0.0.0.0/0` | All Protocols | — | Allow all outbound |

### 7.2 Private security list

![Figure 9 — Private security list rules](../screenshots/console/fig09-sl-private-rules.png)

*Figure 9. `ejada-w2-dev-sl-private` — ingress ICMP type 3 code 4 restricted to the VCN CIDR; egress all protocols.*

| Direction | Source / Destination | Protocol | Type & Code | Purpose |
|---|---|---|---|---|
| Ingress | `10.0.0.0/16` | ICMP | 3, 4 | Path MTU discovery, VCN-internal only |
| Egress | `0.0.0.0/0` | All Protocols | — | Allow all outbound |

### 7.3 Why security lists and NSGs are both used

| | Security List | Network Security Group |
|---|---|---|
| Attached to | A **subnet** — applies to every VNIC in it | Specific **VNICs** |
| Rule sources | CIDR or service only | CIDR, service, **or another NSG** |
| Membership | Implicit (be in the subnet) | Explicit (attach the NSG) |

OCI evaluates the two as a **union**: a packet is permitted if *either* the subnet's security list **or** an attached NSG allows it. Neither can override the other to deny.

That union behaviour is what makes the split used here safe. Because an NSG rule can name another NSG as its source, a rule can express *"only the load balancer may reach the application"* rather than *"anything in 10.0.1.0/24 may reach the application"* — so if another resource is later placed in the public subnet, it does not silently inherit access to the private tier. Keeping the subnet-wide lists thin and the intent-specific rules in NSGs is the pattern Oracle's own reference architectures use.

The ICMP type 3 code 4 rule ("Destination Unreachable: Fragmentation Needed") is included in both lists because path MTU discovery depends on it. If it is blocked, oversized packets are dropped without any error being returned, which presents as connections that hang rather than fail — a failure mode that is disproportionately hard to diagnose relative to the cost of the rule.

---

## 8. Network Security Groups

Three NSGs were created, one per tier. Unlike the security lists in Section 7, these carry the actual application rules — and, critically, several of them use **another NSG as the source or destination** rather than a CIDR block.

**NSG Summary**

| NSG | Attached to (Section 9 onward) | Rules | Created (UTC) |
|---|---|---|---|
| `ejada-w2-dev-nsg-lb` | Load balancer | 2 | Aug 12, 2026, 16:53:37 |
| `ejada-w2-dev-nsg-app` | Compute instance VNIC | 3 | Aug 12, 2026, 16:57:51 |
| `ejada-w2-dev-nsg-fss` | File Storage mount target | 5 | Aug 12, 2026 |

`nsg-lb` OCID: `ocid1.networksecuritygroup.oc1.me-jeddah-1.aaaaaaaa2crhynwlhkopibp3x6e7lxlgd643aswg7oim6jmth3kjegyq4gza`
`nsg-app` OCID: `ocid1.networksecuritygroup.oc1.me-jeddah-1.aaaaaaaal76fbbtbumtcwymioli4fgt3uooncxmnrnz3ww5nrchxoe2h3okq`

### 8.1 `ejada-w2-dev-nsg-lb` — load balancer tier

![Figure 10 — nsg-lb rules](../screenshots/console/fig11-nsg-lb-rules.png)

*Figure 10. `ejada-w2-dev-nsg-lb` security rules — ingress TCP 80 from any client, egress TCP 80 to the application NSG.*

| Direction | Source / Destination | Type | Protocol | Port | Purpose |
|---|---|---|---|---|---|
| Ingress | `0.0.0.0/0` | CIDR | TCP | 80 | Client HTTP traffic to the listener |
| Egress | `ejada-w2-dev-nsg-app` | **NSG** | TCP | 80 | Forwarded requests and health checks |

### 8.2 `ejada-w2-dev-nsg-app` — application tier

![Figure — nsg-app rules](../screenshots/console/fig18-nsg-app-rules.png)

*Figure. `ejada-w2-dev-nsg-app` security rules — note the ingress rule whose Source Type is **NSG** and whose Source is `ejada-w2-dev-nsg-lb`, rather than a CIDR block.*

| Direction | Source / Destination | Type | Protocol | Port | Purpose |
|---|---|---|---|---|---|
| Ingress | `ejada-w2-dev-nsg-lb` | **NSG** | TCP | 80 | Only the load balancer may reach the app |
| Ingress | `10.0.0.0/16` | CIDR | TCP | 22 | SSH from the OCI Bastion private endpoint |
| Egress | `0.0.0.0/0` | CIDR | All | — | Package installs via NAT, NFS to the mount target |

The port 22 rule is sourced from the VCN CIDR rather than a public IP because the OCI Bastion service does not connect from the administrator's workstation. It provisions a private endpoint **inside this VCN** and brokers the session from there, so from the instance's perspective the SSH connection originates internally.

### 8.3 `ejada-w2-dev-nsg-fss` — File Storage tier

![Figure 11 — nsg-fss rules](../screenshots/console/fig10-nsg-fss-rules.png)

*Figure 11. `ejada-w2-dev-nsg-fss` security rules — the four NFS ingress rules sourced from the application NSG, plus an egress rule back to it.*

| Direction | Source / Destination | Type | Protocol | Port | Purpose |
|---|---|---|---|---|---|
| Ingress | `ejada-w2-dev-nsg-app` | **NSG** | TCP | 111 | rpcbind / portmapper |
| Ingress | `ejada-w2-dev-nsg-app` | **NSG** | TCP | 2048–2050 | mountd, nfsd, statd |
| Ingress | `ejada-w2-dev-nsg-app` | **NSG** | UDP | 111 | rpcbind / portmapper |
| Ingress | `ejada-w2-dev-nsg-app` | **NSG** | UDP | 2048 | mountd |
| Egress | `ejada-w2-dev-nsg-app` | **NSG** | All | — | Traffic the mount target initiates |

All five rules are **stateful** (Stateless = No), so replies to the four ingress rules are permitted automatically and no matching egress rules are required for them. The single egress rule covers only traffic the mount target originates itself.

If any of these six NFS ports is missing, the `mount` command on the instance does not return an error — it hangs until it times out, because the RPC negotiation never completes. This is the most common cause of a failed File Storage lab and is the reason the ports are configured before the instance exists rather than after.

### 8.4 An ordering constraint that Terraform removes

The `nsg-lb` egress rule could not be created at the same time as `nsg-lb` itself, because it names `nsg-app` as its destination and `nsg-app` did not yet exist. In the Console the work therefore has to be sequenced by hand: create `nsg-lb` with only its ingress rule, create `nsg-app`, then return to `nsg-lb` and add the egress rule.

Terraform removes this constraint entirely. Because `oci_core_network_security_group_security_rule.lb_egress_app` references `oci_core_network_security_group.app.id`, Terraform infers the dependency, builds a graph, and creates the resources in a valid order without the author sequencing anything. This is a concrete, small example of the difference between imperative clicking and declarative infrastructure — and a good answer to "why bother with IaC for something this small".

---

## 9. Subnets

Two **regional** subnets were carved out of the VCN's `10.0.0.0/16`, one per tier. Creating them is the point at which the route tables and security lists from Sections 6 and 7 stop being inert definitions and start governing traffic — a subnet is where a route table, a security list and an address range are bound together.

![Figure 12 — Subnets](../screenshots/console/fig12-subnets-list.png)

*Figure 12. Subnets in `ejada-w2-dev-vcn` — `10.0.2.0/24` Private (Regional) and `10.0.1.0/24` Public (Regional).*

**Subnet Summary**

| Attribute | Public subnet | Private subnet |
|---|---|---|
| Name | `ejada-w2-dev-subnet-public` | `ejada-w2-dev-subnet-private` |
| IPv4 CIDR Block | `10.0.1.0/24` | `10.0.2.0/24` |
| Subnet Type | Regional | Regional |
| Subnet Access | **Public** | **Private** |
| Route Table | `ejada-w2-dev-rt-public` | `ejada-w2-dev-rt-private` |
| Security List | `ejada-w2-dev-sl-public` | `ejada-w2-dev-sl-private` |
| DNS Label | `public` | `private` |
| State | Available | Available |
| Created (UTC) | Aug 12, 2026, 18:15:54 | Aug 12, 2026, 18:16:43 |
| Contains | Application Load Balancer | Compute instance, File Storage mount target |

### 9.1 Regional rather than availability-domain-specific

Both subnets are regional, meaning they span every availability domain in `me-jeddah-1` rather than being pinned to one. Oracle recommends regional subnets for new designs: resources can be placed in any AD without re-planning the address space, and the subnet survives the loss of a single AD. AD-specific subnets exist mainly for older architectures that need to guarantee physical placement.

### 9.2 What "Private Subnet" actually enforces

Selecting **Private Subnet** sets the subnet's `prohibit_public_ip_on_vnic` attribute to true. This is an enforced constraint rather than a default: the Console will not offer to assign a public IP to an instance launched into this subnet, and an API call that requests one is rejected.

This distinction matters for the report's central claim. The application instance in Section 11 has no public IP not because that option was left unticked at launch, but because the subnet it lives in makes a public IP impossible. The guarantee is structural, and it stays true for anything else launched there later.

### 9.3 A note on the default security list

The Create Subnet form pre-selects the VCN's **Default Security List**. It was removed and replaced with the purpose-built list for each tier. Leaving it attached would have added its permissive default rules — including SSH from `0.0.0.0/0` — alongside the intended ones. Because OCI evaluates security lists and NSGs as a union (Section 7.3), those extra rules cannot be overridden by anything else in the design; they would simply have widened the attack surface while the configuration still *looked* locked down.

---

## 10. File Storage (File System, Mount Target, Export)

OCI File Storage provides the shared, NFS-mounted storage that holds the application's files. This satisfies the lab requirement that *"the application files must be stored on OCI File Storage Service (mounted to the instance)"* — the files do not live on the instance's boot volume, so the instance is disposable and the data is not.

Three distinct objects are involved, and the distinction matters:

| Object | What it is |
|---|---|
| **File system** | The storage itself. Has an OCID and an availability domain, but no IP address and no network presence. |
| **Mount target** | The NFS endpoint. Lives in a subnet, holds a private IP, and is what clients actually connect to. |
| **Export** | The binding between the two, published at a path. Carries the access rules. |

### 10.1 File system

![Figure 13 — File system details](../screenshots/console/fig13-fs-details.png)

*Figure 13. `ejada-w2-dev-fs` — Active, availability domain oXVt:ME-JEDDAH-1-AD-1, compartment intern-04-andrew-hany-cmp.*

| Attribute | Value |
|---|---|
| Name | `ejada-w2-dev-fs` |
| State | Active |
| Availability Domain | `oXVt:ME-JEDDAH-1-AD-1` |
| Compartment | `intern-04-andrew-hany-cmp` |
| Utilization | 0 B at creation |
| Created | Wed, Aug 12, 2026, 18:26:21 UTC |

File Storage is billed on data actually written rather than on a provisioned size, so no capacity had to be chosen up front. This is a meaningful difference from the block volume attached in Week 1, which was provisioned at a fixed 1 TB.

### 10.2 Mount target

![Figure 14 — Mount target](../screenshots/console/fig15-mount-target.png)

*Figure 14. `ejada-w2-dev-mt` — Active, private IP 10.0.2.177, in subnet ejada-w2-dev-subnet-private.*

| Attribute | Value |
|---|---|
| Name | `ejada-w2-dev-mt` |
| State | Active |
| Availability Domain | `oXVt:ME-JEDDAH-1-AD-1` |
| VCN | `ejada-w2-dev-vcn` |
| **Subnet** | **`ejada-w2-dev-subnet-private`** |
| **IP address** | **`10.0.2.177`** |
| Created | Aug 12, 2026, 18:26 UTC |

The mount target sits in the **private** subnet, not the public one. An NFS endpoint placed in a subnet with a route to the internet gateway would be reachable from a far larger surface than intended, for no benefit — the only client is the application instance, which lives in the same subnet. Keeping both in `10.0.2.0/24` also means the NFS traffic never crosses a subnet boundary.

`10.0.2.177` is the address used in the mount command in Section 13. It was assigned automatically by OCI from the subnet's range.

### 10.3 Network Security Group attachment

![Figure 15 — Mount target NSG](../screenshots/console/fig16-mt-nsg.png)

*Figure 15. Attaching `ejada-w2-dev-nsg-fss` to the mount target.*

The NSG is attached to the mount target after creation, since the create form does not expose the field. This step is easy to skip and silently consequential: the five NFS rules built in Section 8.3 apply to VNICs in `nsg-fss`, so until the mount target is a member of that NSG, those rules govern nothing.

### 10.4 Export and NFS client export options

![Figure 16 — Export](../screenshots/console/fig14-fs-export.png)

*Figure 16. The `/app` export in Active state.*

![Figure 17 — Export options](../screenshots/console/fig17-export-options.png)

*Figure 17. NFS client export options — source narrowed to the private subnet CIDR, read/write, anonymous access not allowed.*

| Option | Value | Reason |
|---|---|---|
| Export path | `/app` | Path published by the mount target |
| Source | `10.0.2.0/24` | Only the private subnet may mount |
| Ports | Any | Clients need not use privileged source ports |
| Access | Read/Write | The application writes as well as reads |
| Anonymous access | Not allowed | No identity squashing — root stays root |
| Allowed authentication | SYS | Standard AUTH_SYS; Kerberos is not configured |

Two of these are worth defending.

**Source `10.0.2.0/24` rather than the default `0.0.0.0/0`.** The export is created wide open and must be narrowed deliberately. Combined with the NSG in Section 8.3 this gives two independent layers: the NSG controls which VNICs can reach the endpoint at all, and the export options control which addresses the NFS server itself will serve. Either alone would be sufficient in this topology; both together mean a mistake in one does not expose the data.

**Anonymous access "Not allowed"** — the console's presentation of `identity_squash = NONE`. With squashing enabled, the root user on the client is remapped to an anonymous UID; the `chown apache:apache` performed on the mount in Section 13 would then fail with a permission error that gives no hint that NFS identity mapping is the cause. Disabling it keeps UIDs consistent between the instance and the share.

---

## 11. Compute Instance

The application server, `ejada-w2-dev-app`, was launched into the **private** subnet with **no public IP address**. This is the central requirement of the lab: the workload must be unreachable from the internet directly, and reachable only through the load balancer in the public subnet.

**Instance Summary**

| Attribute | Value |
|---|---|
| Name | `ejada-w2-dev-app` |
| Compartment | `intern-04-andrew-hany-cmp` |
| Availability Domain | AD-1 (`oXVt:ME-JEDDAH-1-AD-1`) |
| Fault Domain | FD-1 (Oracle-selected) |
| Region | me-jeddah-1 |
| OCID | `ocid1.instance.oc1.me-jeddah-1.anvgkljrvjakbnic5n36gge4rnjcl3a42br55svrj3ydozkmxsfucfr5x3ua` |
| Launched | Aug 12, 2026, 18:54:31 UTC |
| State | Running |
| Capacity Type | On-demand |
| NIC attachment / boot volume | Paravirtualized |
| In-transit encryption | Enabled |
| Firmware | UEFI_64 |
| Operating System | Oracle Linux 9 |
| Image Build | `2026.07.20-1` |
| Shape | `VM.Standard.E5.Flex` |
| Shape Build | 1 core OCPU, 12 GB memory, 1 Gbps network bandwidth |
| SMT | Enabled |

The instance is placed in the same availability domain as the File Storage mount target. Instances can mount a file system across availability domains, but doing so adds network latency for no benefit when both can sit in AD-1.

### 11.1 Networking — the evidence for the core requirement

![Figure 18 — Instance networking](../screenshots/console/fig19-instance-networking.png)

*Figure 18. `ejada-w2-dev-app` Primary VNIC — **Public IPv4 address is empty**, private IPv4 10.0.2.233, private route table, and the `ejada-w2-dev-nsg-app` security group attached.*

| Attribute | Value |
|---|---|
| **Public IPv4 address** | **— (none)** |
| Private IPv4 address | `10.0.2.233` |
| Subnet | `ejada-w2-dev-subnet-private` |
| Route table | `ejada-w2-dev-rt-private` |
| Network security group | `ejada-w2-dev-nsg-app` |
| Private DNS record | Enabled |
| Hostname | `app-vnic` |
| Internal FQDN | `app-vnic.private.ejadaw2dev.oraclevcn.com` |

This single view demonstrates the whole design:

- **No public IP** — nothing on the internet can address this host directly. This is enforced by the subnet (Section 9.2), not merely chosen at launch.
- **`10.0.2.233`** — the address the load balancer backend set targets in Section 14, and the address the mount target at `10.0.2.177` serves NFS to.
- **`ejada-w2-dev-rt-private`** — outbound traffic leaves via the NAT gateway, so package installation works while inbound connections remain impossible.
- **`ejada-w2-dev-nsg-app`** — the three rules from Section 8.2 now apply to a real VNIC.

The internal FQDN is resolvable from anywhere inside the VCN and could have been used in place of the IP address for the load balancer backend. The IP was used instead because the OCI Load Balancer backend definition takes an IP address.

### 11.2 Attaching the NSG after launch

The Create Instance wizard's **"Use network security groups to control traffic"** toggle could not be enabled during creation — it remained greyed out with the message *"Select a VCN before using network security groups"* even after the VCN and subnet were both correctly selected.

Rather than continue debugging the form, the instance was created without an NSG and the group was attached afterwards via **Instance → Attached VNICs → primary VNIC → Edit → Network security groups**. NSG membership is a mutable property of a VNIC, so the end state is identical.

This is recorded as Issue 3 in Section 15, and it is the second Console limitation this lab has produced that Terraform does not have.

---

## 12. Bastion Access

_Pending — Step 1.9_

---

## 13. Application Deployment & NFS Mount

_Pending — Step 1.10_

---

## 14. Load Balancer

_Pending — Step 1.11_

---

## 15. Troubleshooting

_Issues are recorded here as they happen — including ones that were my own mistake. A report with an honest troubleshooting section reads as more credible than one where everything worked first try._

### Issue 1 — Sign-in rejected at the Cloud Account Name prompt

**Symptom.** The Oracle Cloud sign-in page returned *"That name didn't work, want to try again?"*.

**Cause.** The **Cloud Account Name** field expects the **tenancy name**, not a user email address. An email address had been entered.

**Resolution.** Signed in with tenancy `ociejada`, then selected identity domain **Ejada-interim-program** (not `Default`), then supplied the username `andrew.hany.e@gmail.com` and a one-time passcode. The direct URL `https://console.me-jeddah-1.oraclecloud.com/?tenant=ociejada&domain=Ejada-interim-program` bypasses both prompts.

### Issue 2 — "Authorization failed or requested resource not found" on the Compartments page

**Symptom.** Opening **Identity & Security → Compartments → intern-04-andrew-hany-cmp** returned *Authorization failed or requested resource not found*, so the compartment OCID could not be copied from the Console.

**Cause.** The intern user is granted `manage` on the resources *inside* the assigned compartment, but not `read` on the compartment object in the IAM service. This is expected least-privilege behaviour in a shared training tenancy, not a misconfiguration.

**Resolution.** The OCID was retrieved indirectly from a resource already owned in that compartment, using the pre-authenticated OCI CLI in Cloud Shell — reading a VCN requires only networking permissions:

```bash
oci network vcn get \
  --vcn-id ocid1.vcn.oc1.me-jeddah-1.amaaaaaavjakbniamrjvpoavw6ikbuj5miewklpaovhjuqs3k746oivkhq2a \
  --query 'data."compartment-id"' --raw-output
```

**Takeaway.** Every OCI resource carries its `compartment-id`, so a compartment OCID can always be recovered from any resource inside it without IAM read access.

### Issue 3 — NSG toggle disabled in the Create Instance wizard

**Symptom.** In the Networking step of Create Instance, the **"Use network security groups to control traffic"** toggle was permanently greyed out, with the hint *"Select a VCN before using network security groups"*. The VCN and subnet were both selected correctly, and re-selecting them did not enable the control. An initial review of the instance showed `Use network security groups to control traffic: No`, which would have launched the instance with no NSG at all.

**Impact if unnoticed.** The private subnet's security list permits only ICMP. With no NSG attached, the instance would have been unreachable on port 80 and port 22 — the load balancer backend would have reported Critical and the bastion session would have failed, with neither symptom pointing at the actual cause.

**Resolution.** The instance was created without an NSG, then `ejada-w2-dev-nsg-app` was attached afterwards through **Instance → Attached VNICs → primary VNIC → Edit → Network security groups**. NSG membership is a mutable VNIC property, so the resulting configuration is identical to attaching it at launch.

**Takeaway.** Two of the frictions in this lab — this one, and the NSG-to-NSG rule ordering in Section 8.4 — disappear entirely in Terraform, where the NSG is simply a field on the VNIC:

```hcl
create_vnic_details {
  subnet_id        = oci_core_subnet.private.id
  assign_public_ip = false
  nsg_ids          = [oci_core_network_security_group.app.id]
}
```

---

## 16. Final Verification & Checklist

| Verification Item | Status | Evidence |
|---|---|---|
| VCN created with 10.0.0.0/16 | | |
| Public subnet 10.0.1.0/24 created | | |
| Private subnet 10.0.2.0/24 created, public IPs prohibited | | |
| Internet, NAT and Service gateways Available | | |
| Public route table 0.0.0.0/0 → IGW | | |
| Private route table 0.0.0.0/0 → NAT, OSN → SGW | | |
| Three NSGs created with NSG-to-NSG rules | | |
| File system and mount target created in the private subnet | | |
| Export `/app` published with correct export options | | |
| Instance launched with **no public IP** | | |
| Bastion managed SSH session established | | |
| File Storage export mounted at `/var/www/html` (nfs) | | |
| Apache serving files from the NFS mount | | |
| Load balancer backend health **OK** | | |
| Application reachable at the LB public IP from a browser | | |

---

## 17. Architecture Diagram

See `architecture.drawio`.

---

## 18. Technical Summary

_Pending._

---

## 19. Conclusion

_Pending._
