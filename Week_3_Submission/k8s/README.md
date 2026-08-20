# Kubernetes manifests

Applied in filename order:

```bash
kubectl apply -f k8s/
```

| File | Resource | What it demonstrates |
|---|---|---|
| `00-namespace.yaml` | Namespace `ejada-w3` | isolation |
| `10-pvc.yaml` | PersistentVolumeClaim | **external block volume** via the `oci-bv` CSI storage class |
| `20-deployment.yaml` | Deployment | NGINX serving content **off the volume**, seeded by an init container |
| `30-service-lb.yaml` | Service type `LoadBalancer` | **OCI Load Balancer**, provisioned by the cluster |

## Three things that look like bugs and are not

**1. The PVC sits `Pending` at first.**
`oci-bv` uses `volumeBindingMode: WaitForFirstConsumer`. The block volume is
not created until a pod is actually scheduled, so that the volume lands in the
same availability domain as the node. `Pending` before scheduling is correct;
`Pending` *after* the pod is Running is a real problem.

**2. `replicas: 1` with `strategy: Recreate`.**
An OCI block volume is `ReadWriteOnce` — one node may mount it at a time. A
second replica on another node would sit `Pending` forever. `Recreate` makes a
rollout terminate the old pod (releasing the volume) before starting the new
one, instead of deadlocking on the attachment.

*If the app needed many replicas sharing storage, the answer would be OCI File
Storage over NFS with `ReadWriteMany` — which is exactly what Week 2 built.
Different storage primitive for a different access pattern.*

**3. `lost+found` appears in the web root.**
The CSI driver formats the raw block device as ext4 on first attach, and ext4
creates `lost+found`. Seeing it is positive evidence: it means the mount is a
real block device, not a container filesystem layer.

## Why the init container

Mounting a volume at `/usr/share/nginx/html` hides whatever the NGINX image
shipped there, so without seeding you get a 403 on an empty directory. The init
container writes `index.html` and `seeded.txt` onto the volume before NGINX
starts.

`seeded.txt` carries a timestamp, which makes the persistence test unambiguous:

```bash
kubectl exec -n ejada-w3 deploy/nginx-demo -- cat /usr/share/nginx/html/seeded.txt
kubectl delete pod -n ejada-w3 -l app=nginx-demo
# wait for the replacement
kubectl exec -n ejada-w3 deploy/nginx-demo -- cat /usr/share/nginx/html/seeded.txt
```

New pod, **same timestamp**. The init container ran again but rewrote the same
file on the same volume — and the volume is what survived. Different pod,
same data.

## Load balancer annotations

```yaml
oci.oraclecloud.com/load-balancer-type: "lb"          # OCI LB; "nlb" for Network LB
service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"   # Mbps
service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
service.beta.kubernetes.io/oci-load-balancer-internal: "false"
```

The LB lands in the subnet registered on the cluster as `service_lb_subnet_ids`,
which Terraform set to the public LB subnet — so no `oci-load-balancer-subnet1`
annotation is needed. It is left commented in the file for reference.

## Cleanup

```bash
kubectl delete -f k8s/
```

Deleting the Service removes the OCI Load Balancer; deleting the PVC removes
the block volume (the storage class `reclaimPolicy` is `Delete`). **Do this
before `terraform destroy`** — otherwise the load balancer keeps a VNIC in the
LB subnet and the subnet delete fails.
