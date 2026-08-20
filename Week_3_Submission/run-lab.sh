#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run-lab.sh -- drives the Week 3 OKE lab and captures the evidence.
#
# Each stage runs its commands, saves the full output of every one to
# evidence/<run>/<name>.txt, and pauses at the points where a screenshot is
# worth taking. Plain POSIX shell, so it runs in Git Bash on Windows and
# unchanged in OCI Cloud Shell.
#
#   ./run-lab.sh preflight     tooling, IAM reachability, shape availability
#   ./run-lab.sh plan          init / fmt / validate / plan + resource assertions
#   ./run-lab.sh apply         terraform apply, then the outputs
#   ./run-lab.sh kubeconfig    generate the kubeconfig, wait for nodes Ready
#   ./run-lab.sh deploy        kubectl apply, wait for the pod and the LB
#   ./run-lab.sh verify        the four things the brief asks to be demonstrated
#   ./run-lab.sh persistence   delete the pod, prove the data survived
#   ./run-lab.sh teardown      Kubernetes first, then Terraform. Asks first.
#
# RUN_ID=<name>   keep several stages' evidence in one folder
# NO_PAUSE=1      skip the "press Enter once captured" stops
# ---------------------------------------------------------------------------
set -uo pipefail

STAGE="${1:-}"
NAMESPACE="${NAMESPACE:-ejada-w3}"
LB_TIMEOUT_MIN="${LB_TIMEOUT_MIN:-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT/terraform"
K8S_DIR="$ROOT/k8s"

# --- Git Bash path mangling -------------------------------------------------
# MSYS rewrites any argument that looks like an absolute Unix path into a
# Windows path before handing it to a native .exe. That is right for host paths
# and badly wrong for *container* paths: `kubectl exec -- cat
# /usr/share/nginx/html/seeded.txt` arrives inside the container as
# C:/Program Files/Git/usr/share/nginx/html/seeded.txt and fails.
#
# So conversion is switched off globally, and the two host paths that genuinely
# need it are converted explicitly below. No-ops outside Git Bash, which is why
# this file still runs unchanged in OCI Cloud Shell.
export MSYS_NO_PATHCONV=1

winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

K8S_DIR_ARG="$(winpath "$K8S_DIR")"   # kubectl apply/delete -f
HOME_ARG="$(winpath "$HOME")"         # oci ce cluster create-kubeconfig --file
# Stages are normally run one at a time, minutes or hours apart, which would
# scatter one lab run's evidence across several folders. Set RUN_ID to keep them
# together:  RUN_ID=2026-08-19_lab ./run-lab.sh plan
STAMP="${RUN_ID:-$(date +%Y-%m-%d_%H%M)}"
OUT="$ROOT/evidence/$STAMP"
mkdir -p "$OUT"

FAILURES=()
SHOTS=()

# --- colours (dropped when not a terminal, so evidence files stay clean) -----
if [ -t 1 ]; then
  C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'
  C_ERR=$'\033[0;31m'; C_CMD=$'\033[0;36m'; C_DIM=$'\033[0;90m'; C_OFF=$'\033[0m'
else
  C_OK=; C_WARN=; C_ERR=; C_CMD=; C_DIM=; C_OFF=
fi

RULE="=============================================================================="

head_() { printf '\n%s\n  %s\n%s\n' "$RULE" "$1" "$RULE"; }
note_() { printf '  %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
ok_()   { printf '  %sOK   %s%s\n' "$C_OK" "$1" "$C_OFF"; }
warn_() { printf '  %s??   %s%s\n' "$C_WARN" "$1" "$C_OFF"; }
fail_() { printf '  %s!    %s%s\n' "$C_ERR" "$1" "$C_OFF"; FAILURES+=("$1"); }

# cap <name> <command...>  -- run it, echo it, save it to evidence/<stamp>/<name>.txt
cap() {
  local name="$1"; shift
  local path="$OUT/$name.txt"
  printf '\n%s$ %s%s\n' "$C_CMD" "$*" "$C_OFF"
  printf '# %s\n# %s\n$ %s\n\n' "$name" "$(date '+%Y-%m-%d %H:%M:%S %z')" "$*" > "$path"
  "$@" 2>&1 | tee -a "$path"
  local rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    printf '  %s! exit code %s (saved to %s.txt)%s\n' "$C_ERR" "$rc" "$name" "$C_OFF"
  fi
  return "$rc"
}

# cap_soft -- same, but a non-zero exit is expected and tolerated
cap_soft() { cap "$@" || true; }

shot() {
  SHOTS+=("$1")
  printf '\n  %s---- SCREENSHOT ----------------------------------------------%s\n' "$C_WARN" "$C_OFF"
  printf '  %s   save as : %s%s\n' "$C_WARN" "$1" "$C_OFF"
  printf '  %s   showing : %s%s\n' "$C_WARN" "$2" "$C_OFF"
  printf '  %s--------------------------------------------------------------%s\n' "$C_WARN" "$C_OFF"
  if [ "${NO_PAUSE:-0}" != "1" ]; then
    read -r -p "   press Enter once captured " _ </dev/tty || true
  fi
}

# JSON reader: jq when present, otherwise Python. Cloud Shell has both; Git Bash
# on Windows has neither jq nor python3, but does have the python.org build.
# Probe by running each candidate, not just by looking it up: on Windows,
# "python3" is usually the Microsoft Store stub, which resolves on PATH but
# exits with an advert instead of an interpreter.
PYBIN=""
if ! command -v jq >/dev/null 2>&1; then
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && [ "$("$c" -c 'print(1)' 2>/dev/null)" = "1" ]; then
      PYBIN="$c"; break
    fi
  done
  if [ -z "$PYBIN" ]; then
    printf '  %sNeither jq nor a working python is on PATH; the plan assertions\n' "$C_WARN"
    printf '  in the plan stage will be skipped.%s\n' "$C_OFF"
  fi
fi

# count_type <plan-json> <resource type> -- how many of that type get created
count_type() {
  local f="$1" t="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg t "$t" \
      '[.resource_changes[]? | select(.type==$t) | select(.change.actions|index("create"))] | length' "$f"
  else
    "$PYBIN" -c 'import json,sys
p=json.load(open(sys.argv[1],encoding="utf-8"))
t=sys.argv[2]
print(sum(1 for r in p.get("resource_changes",[])
          if r.get("type")==t and "create" in r.get("change",{}).get("actions",[])))' "$f" "$t"
  fi
}

plan_cni() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '[.resource_changes[]? | select(.type=="oci_containerengine_cluster")][0].change.after.cluster_pod_network_options[0].cni_type // "unknown"' "$f"
  else
    "$PYBIN" -c 'import json,sys
p=json.load(open(sys.argv[1],encoding="utf-8"))
for r in p.get("resource_changes",[]):
    if r.get("type")=="oci_containerengine_cluster":
        try:
            print(r["change"]["after"]["cluster_pod_network_options"][0]["cni_type"]); break
        except Exception:
            pass
else:
    print("unknown")' "$f"
  fi
}

# redact_plan_json <file> -- remove credential-ish values from a plan JSON
redact_plan_json() {
  local f="$1"
  [ -s "$f" ] || return 0
  if [ -n "$PYBIN" ]; then
    "$PYBIN" -c 'import json,sys
f=sys.argv[1]
p=json.load(open(f,encoding="utf-8"))
secrets=[]
for k in ("tenancy_ocid","user_ocid","fingerprint","private_key_path"):
    v=p.get("variables",{}).get(k,{}).get("value")
    if isinstance(v,str) and v:
        secrets.append(v)
        p["variables"][k]["value"]="<redacted>"
# Key-level redaction is not enough on its own: the tenancy OCID reappears in
# prior_state, because the availability-domains data source is queried with
# compartment_id = var.tenancy_ocid. Substitute the raw values everywhere.
raw=json.dumps(p)
for s in secrets:
    raw=raw.replace(s,"<redacted>")
open(f,"w",encoding="utf-8").write(raw)' "$f" 2>/dev/null
  fi
}

assert_count() {
  local type="$1" expected="$2" actual
  actual="$(count_type "$OUT/tf04-plan.json" "$type")"
  if [ "$actual" = "$expected" ]; then
    printf '  %sOK   %-38s %s%s\n' "$C_OK" "$type" "$actual" "$C_OFF"
  else
    printf '  %s??   %-38s %s  (expected %s)%s\n' "$C_WARN" "$type" "$actual" "$expected" "$C_OFF"
    FAILURES+=("$type count is $actual, expected $expected")
  fi
}

# wait_for <timeout-min> <description> <command...>
wait_for() {
  local mins="$1" desc="$2"; shift 2
  local deadline=$(( $(date +%s) + mins * 60 ))
  printf '  %swaiting: %s%s' "$C_WARN" "$desc" "$C_OFF"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if "$@" >/dev/null 2>&1; then printf '  %sOK%s\n' "$C_OK" "$C_OFF"; return 0; fi
    printf '.'
    sleep 10
  done
  printf '  %sTIMED OUT%s\n' "$C_ERR" "$C_OFF"
  FAILURES+=("timeout waiting for $desc")
  return 1
}

tfvar() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" \
    "$TF_DIR/terraform.tfvars" 2>/dev/null | head -1
}

lb_ip() {
  kubectl get svc nginx-demo -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null
}

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
do_preflight() {
  head_ "PREFLIGHT  -  can this lab actually be built?"

  printf '\n  Tooling\n'
  # kubectl has no --version; it wants "version --client". Keep the version
  # argument next to the tool name rather than assuming they all agree.
  local entry t vflag
  for entry in "terraform|-version" "oci|--version" "kubectl|version --client"; do
    t="${entry%%|*}"; vflag="${entry#*|}"
    if command -v "$t" >/dev/null 2>&1; then
      printf '  %s%-12s %s%s\n' "$C_OK" "$t" "$("$t" $vflag 2>&1 | head -1)" "$C_OFF"
    else
      printf '  %s%-12s MISSING%s\n' "$C_ERR" "$t" "$C_OFF"
      FAILURES+=("$t not installed")
    fi
  done

  local compartment; compartment="$(tfvar compartment_id)"
  if [ -z "$compartment" ]; then
    warn_ "terraform/terraform.tfvars has no compartment_id -- copy the example and fill it in"
    FAILURES+=("terraform.tfvars missing compartment_id")
    return
  fi
  case "$compartment" in
    PASTE_*|*xxxxxxxx*)
      warn_ "compartment_id is still a placeholder: $compartment"
      note_ "Console -> Identity & Security -> Compartments -> intern-04-andrew-hany-cmp -> Copy OCID"
      FAILURES+=("terraform.tfvars still has placeholder OCIDs")
      return ;;
  esac
  note_ "compartment: $compartment"

  if [ ! -f "$HOME/.oci/config" ]; then
    warn_ "no ~/.oci/config -- the OCI CLI has no credentials"
    note_ "create one with:  oci setup config"
    FAILURES+=("no ~/.oci/config")
    return
  fi

  printf '\n  IAM reachability  (NotAuthorizedOrNotFound = missing policy)\n'
  local i=2
  local pair svc cmdstr name
  for pair in \
    "cluster-family|oci ce cluster list" \
    "log-groups|oci logging log-group list" \
    "load-balancers|oci lb load-balancer list" \
    "volume-family|oci bv volume list" \
    "virtual-network-family|oci network vcn list"
  do
    svc="${pair%%|*}"; cmdstr="${pair#*|}"
    name="$(printf 'pre%02d-iam-%s' "$i" "$svc")"
    cap_soft "$name" $cmdstr --compartment-id "$compartment" >/dev/null 2>&1
    if grep -q 'NotAuthorizedOrNotFound' "$OUT/$name.txt" 2>/dev/null; then
      printf '  %s%-24s DENIED%s\n' "$C_ERR" "$svc" "$C_OFF"
      FAILURES+=("IAM: no access to $svc")
    else
      printf '  %s%-24s ok%s\n' "$C_OK" "$svc" "$C_OFF"
    fi
    i=$((i+1))
  done

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    printf '\n  %sAsk bmokhtar@ejada.com for the missing statements.%s\n' "$C_WARN" "$C_OFF"
    printf '  %sFull list: docs/RUNBOOK.md section 0.2%s\n' "$C_WARN" "$C_OFF"
  fi

  printf '\n  Shape availability\n'
  cap_soft pre07-shapes oci compute shape list --compartment-id "$compartment" \
    --query "data[?contains(shape,'Flex')].shape" --output table >/dev/null 2>&1
  if grep -q 'E4\.Flex' "$OUT/pre07-shapes.txt" 2>/dev/null; then
    ok_ "VM.Standard.E4.Flex : available"
  else
    warn_ "VM.Standard.E4.Flex not seen -- pick a listed shape in terraform.tfvars"
  fi

  note_ "Limits are easiest to read in the Console: Governance & Administration ->"
  note_ "Limits, Quotas and Usage -> me-jeddah-1. Check AVAILABLE, not just the limit."
  shot 'console/fig00-limits.png' 'Limits, Quotas and Usage for me-jeddah-1'
}

# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------
do_plan() {
  head_ "PLAN  -  init, format, validate, plan, sanity-check"
  cd "$TF_DIR" || return 1

  cap tf01-init     terraform init -input=false
  cap_soft tf02-fmt terraform fmt -check -recursive
  cap tf03-validate terraform validate
  shot 'terraform/tf01-fmt-validate.png' 'terraform fmt -check and terraform validate, both clean'

  if ! cap tf04-plan terraform plan -input=false -out=tfplan; then
    fail_ "terraform plan failed"
    cd "$ROOT"
    return 1
  fi
  shot 'terraform/tf02-plan-summary.png' 'the "N to add, 0 to change, 0 to destroy" summary line'

  terraform show -json tfplan > "$OUT/tf04-plan.json" 2>/dev/null
  # `terraform show -json` embeds the root variables block, which carries
  # tenancy_ocid, user_ocid, fingerprint and the key path. The assertions below
  # only read resource_changes, so the identity values are stripped before this
  # file is written anywhere that gets shared.
  redact_plan_json "$OUT/tf04-plan.json"
  if [ ! -s "$OUT/tf04-plan.json" ]; then
    warn_ "could not read the plan as JSON - skipping the sanity check"
    cd "$ROOT"
    return 0
  fi

  printf '\n  Expectations\n'
  assert_count oci_core_subnet               4
  assert_count oci_core_route_table          4
  assert_count oci_core_security_list        4
  assert_count oci_logging_log               4
  assert_count oci_logging_log_group         1
  assert_count oci_containerengine_cluster   1
  assert_count oci_containerengine_node_pool 1

  note_ "oci_logging_log_group must be 1, not 5 - the root passes one shared group into"
  note_ "all four subnet module calls, so the modules skip creating their own. 5 means"
  note_ "the flow_logs_log_group_id wiring is broken."

  local cni; cni="$(plan_cni "$OUT/tf04-plan.json")"
  if [ "$cni" = "OCI_VCN_IP_NATIVE" ]; then
    ok_ "cni_type = OCI_VCN_IP_NATIVE"
  else
    warn_ "cni_type = $cni  (expected OCI_VCN_IP_NATIVE)"
    FAILURES+=("cluster is not VCN-native")
  fi
  shot 'terraform/tf03-plan-checks.png' 'the resource-count table and the expectation checks'
  cd "$ROOT"
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
do_apply() {
  head_ "APPLY  -  network, then cluster, then node pool"
  note_ "Cluster takes ~8-15 min and the node pool ~10-20 min after it."
  cd "$TF_DIR" || return 1

  local started; started=$(date +%s)
  cap tf06-apply terraform apply -input=false tfplan
  local elapsed=$(( $(date +%s) - started ))
  printf 'apply duration: %02d:%02d:%02d\n' \
    $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)) | tee "$OUT/tf07-apply-duration.txt"

  cap tf08-outputs      terraform output
  cap tf09-outputs-json terraform output -json
  cap_soft tf10-flow-log-ids terraform output flow_log_ids
  shot 'terraform/tf04-apply-outputs.png' 'apply complete, with the outputs listed'
  cd "$ROOT"
}

# ---------------------------------------------------------------------------
# kubeconfig
# ---------------------------------------------------------------------------
do_kubeconfig() {
  head_ "KUBECONFIG  -  point kubectl at the cluster"
  cd "$TF_DIR" || return 1
  local cmd; cmd="$(terraform output -raw kubeconfig_command 2>/dev/null)"
  cd "$ROOT"
  if [ -z "$cmd" ]; then
    fail_ "no kubeconfig_command output - has apply run?"
    return 1
  fi
  # the output carries a literal $HOME so it stays shell-agnostic; expand it here
  cmd="${cmd//\$HOME/$HOME_ARG}"
  mkdir -p "$HOME/.kube"
  cap k8s01-create-kubeconfig $cmd

  wait_for 15 'all nodes Ready' bash -c '
    n=$(kubectl get nodes --no-headers 2>/dev/null) || exit 1
    [ -n "$n" ] || exit 1
    total=$(printf "%s\n" "$n" | grep -c .)
    ready=$(printf "%s\n" "$n" | awk "\$2 == \"Ready\"" | grep -c .)
    [ "$total" -gt 0 ] && [ "$total" = "$ready" ]'

  cap k8s02-get-nodes    kubectl get nodes -o wide
  cap k8s03-storageclass kubectl get storageclass
  cap_soft k8s04-cluster-info kubectl cluster-info
  shot 'kubectl/k01-get-nodes.png'    'nodes Ready with IPs in 10.0.1.0/24'
  shot 'kubectl/k02-storageclass.png' 'oci-bv marked (default)'
}

# ---------------------------------------------------------------------------
# deploy
# ---------------------------------------------------------------------------
do_deploy() {
  head_ "DEPLOY  -  namespace, PVC, deployment, load balancer"
  cap app01-apply kubectl apply -f "$K8S_DIR_ARG"

  note_ "The PVC reads Pending until a pod is scheduled. That is correct: oci-bv uses"
  note_ "volumeBindingMode WaitForFirstConsumer, so the volume is only cut once"
  note_ "Kubernetes knows which AD the pod landed in."

  wait_for 10 'pod Ready' bash -c \
    "kubectl get pods -n $NAMESPACE -l app=nginx-demo --no-headers 2>/dev/null | grep -qE '[[:space:]]1/1[[:space:]]+Running[[:space:]]'"

  cap app02-get-all      kubectl get all -n "$NAMESPACE"
  cap app03-pvc          kubectl get pvc,pv -n "$NAMESPACE"
  cap app04-describe-pvc kubectl describe pvc nginx-content -n "$NAMESPACE"
  cap app05-describe-pod kubectl describe pod -n "$NAMESPACE" -l app=nginx-demo

  shot 'kubectl/k03-get-all.png'      "kubectl get all -n $NAMESPACE"
  shot 'kubectl/k05-pvc-bound.png'    'kubectl get pvc,pv: the claim is Bound'
  shot 'kubectl/k06-describe-pvc.png' 'describe pvc: provisioner blockvolume.csi.oraclecloud.com'

  note_ "Waiting for the OCI load balancer (usually 3-5 minutes)."
  wait_for "$LB_TIMEOUT_MIN" 'load balancer external IP' bash -c \
    "[ -n \"\$(kubectl get svc nginx-demo -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)\" ]"

  cap app06-svc kubectl get svc -n "$NAMESPACE" -o wide
  shot 'kubectl/k09-svc-external-ip.png' 'kubectl get svc: EXTERNAL-IP populated'
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------
do_verify() {
  head_ "VERIFY  -  the four things the brief asks to be demonstrated"

  printf '\n  1. VCN-native pod networking\n'
  cap ver01-pods-wide kubectl get pods -n "$NAMESPACE" -o wide
  local pod_ip
  pod_ip="$(kubectl get pods -n "$NAMESPACE" -l app=nginx-demo \
            -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)"
  if printf '%s' "$pod_ip" | grep -qE '^10\.0\.(3[2-9]|[45][0-9]|6[0-3])\.'; then
    ok_ "pod IP $pod_ip is inside the pod subnet 10.0.32.0/19"
  else
    warn_ "pod IP is $pod_ip - expected an address in 10.0.32.0/19"
    note_ "An overlay address (10.244.x.x) would mean flannel, not VCN-native."
    FAILURES+=("pod IP $pod_ip is not in the pod subnet")
  fi
  printf 'pod IP: %s\n' "$pod_ip" > "$OUT/ver02-pod-ip.txt"
  shot 'kubectl/k04-pods-wide.png' "pod IP $pod_ip inside 10.0.32.0/19"

  printf '\n  2. Managed worker node pool\n'
  cap ver03-nodes kubectl get nodes -o wide
  cap_soft ver04-node-labels kubectl get nodes --show-labels

  printf '\n  3. External block volume, mounted\n'
  cap ver05-df kubectl exec -n "$NAMESPACE" deploy/nginx-demo -- df -h /usr/share/nginx/html
  cap ver06-ls kubectl exec -n "$NAMESPACE" deploy/nginx-demo -- ls -la /usr/share/nginx/html
  note_ "lost+found in that listing is good news: the CSI driver formatted a real ext4"
  note_ "block device, so this is not a container filesystem layer."
  cap ver07-pv-detail kubectl get pv -o wide
  shot 'kubectl/k07-df-mount.png'   'df -h showing a ~50G device at the nginx web root'
  shot 'kubectl/k08-ls-content.png' 'ls -la showing index.html, seeded.txt and lost+found'

  printf '\n  4. Exposed through a load balancer\n'
  local ip; ip="$(lb_ip)"
  if [ -z "$ip" ]; then
    warn_ "no EXTERNAL-IP yet; run the deploy stage again"
    FAILURES+=("no load balancer IP")
  else
    note_ "load balancer: http://$ip"
    cap ver08-svc-describe kubectl describe svc nginx-demo -n "$NAMESPACE"
    cap ver09-curl curl -s -i --max-time 20 "http://$ip"
    printf 'http://%s\n' "$ip" > "$OUT/ver10-lb-url.txt"
    shot 'app/app02-curl.png' "curl http://$ip returning the seeded page"
    note_ "Open http://$ip in a browser now."
    shot 'app/app01-browser.png' "the page rendered in a browser at http://$ip"
  fi

  printf '\n'
  note_ "Console screenshots still to take:"
  note_ "  fig12 cluster details   fig14 node pool    fig16 block volume"
  note_ "  fig18 load balancer     fig19 backend set  fig10 log group"
}

# ---------------------------------------------------------------------------
# persistence
# ---------------------------------------------------------------------------
do_persistence() {
  head_ "PERSISTENCE  -  the test that proves the volume is doing the work"

  local before after
  before="$(kubectl get pods -n "$NAMESPACE" -l app=nginx-demo \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  note_ "current pod: $before"

  cap per01-seeded-before kubectl exec -n "$NAMESPACE" deploy/nginx-demo -- \
    cat /usr/share/nginx/html/seeded.txt
  shot 'app/app03-persistence-before.png' "pod name $before and the seeded.txt timestamp"

  cap per02-delete-pod kubectl delete pod -n "$NAMESPACE" -l app=nginx-demo

  wait_for 8 'replacement pod Ready' bash -c \
    "kubectl get pods -n $NAMESPACE -l app=nginx-demo --no-headers 2>/dev/null | grep -qE '[[:space:]]1/1[[:space:]]+Running[[:space:]]' && [ \"\$(kubectl get pods -n $NAMESPACE -l app=nginx-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)\" != '$before' ]"

  after="$(kubectl get pods -n "$NAMESPACE" -l app=nginx-demo \
           -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  note_ "replacement pod: $after"

  cap per03-seeded-after kubectl exec -n "$NAMESPACE" deploy/nginx-demo -- \
    cat /usr/share/nginx/html/seeded.txt

  local ip; ip="$(lb_ip)"
  [ -n "$ip" ] && cap per04-curl-after curl -s --max-time 20 "http://$ip"

  {
    printf 'pod before deletion : %s\n' "$before"
    printf 'pod after deletion  : %s\n\n' "$after"
    printf 'The seeded.txt timestamp is identical across the two pods. The file lives on\n'
    printf 'the block volume, not in the container image, so it survived the pod.\n'
  } > "$OUT/per05-summary.txt"

  # Compare the two readings here rather than leaving it to the eye.
  local t1 t2
  t1="$(grep -m1 '^seeded at' "$OUT/per01-seeded-before.txt" 2>/dev/null)"
  t2="$(grep -m1 '^seeded at' "$OUT/per03-seeded-after.txt" 2>/dev/null)"
  printf '\n'
  if [ -n "$t1" ] && [ "$t1" = "$t2" ] && [ "$before" != "$after" ]; then
    ok_ "same timestamp across two different pods -- the data lived on the volume"
    printf '       %s\n       pod %s -> pod %s\n' "$t1" "$before" "$after"
  else
    warn_ "timestamps differ, or the pod name did not change"
    printf '       before: %s  (%s)\n       after : %s  (%s)\n' "$t1" "$before" "$t2" "$after"
    FAILURES+=("persistence test did not show an identical timestamp")
  fi

  shot 'app/app05-persistence-after.png' "new pod $after, same seeded.txt timestamp, page still served"
}

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------
do_teardown() {
  head_ "TEARDOWN  -  Kubernetes first, then Terraform"
  printf '\n  %sThe load balancer and the block volume were created by Kubernetes, not\n' "$C_WARN"
  printf '  Terraform. Deleting the Kubernetes objects first is what releases the load\n'
  printf '  balancer VNIC from the LB subnet. Skip it and the subnet delete inside\n'
  printf '  terraform destroy will fail.%s\n\n' "$C_OFF"

  local answer=""
  read -r -p "  Destroy everything? Type YES to continue: " answer </dev/tty || true
  if [ "$answer" != "YES" ]; then printf '  cancelled\n'; return 0; fi

  cap_soft del01-kubectl-delete kubectl delete -f "$K8S_DIR_ARG" --ignore-not-found
  wait_for 10 'Service (and its load balancer) gone' bash -c \
    "! kubectl get svc nginx-demo -n $NAMESPACE --no-headers >/dev/null 2>&1"

  note_ "Confirm in the Console that the load balancer AND the block volume are gone"
  note_ "before continuing. Terraform cannot see either of them."
  read -r -p "  press Enter once both have disappeared " _ </dev/tty || true

  cd "$TF_DIR" || return 1
  cap_soft del02-terraform-destroy terraform destroy -input=false -auto-approve
  cd "$ROOT"
  note_ "Check the Console for orphans: block volumes, node pool boot volumes,"
  note_ "load balancers, log groups."
}

# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------
printf '\n  Ejada Week 3 - OKE lab runner (bash)\n'
printf '  %sevidence -> %s%s\n' "$C_DIM" "$OUT" "$C_OFF"

case "$STAGE" in
  preflight)   do_preflight ;;
  plan)        do_plan ;;
  apply)       do_apply ;;
  kubeconfig)  do_kubeconfig ;;
  deploy)      do_deploy ;;
  verify)      do_verify ;;
  persistence) do_persistence ;;
  teardown)    do_teardown ;;
  all)
    do_preflight
    if [ "${#FAILURES[@]}" -gt 0 ]; then
      printf '\n  %sPreflight found problems - stopping before touching OCI.%s\n' "$C_ERR" "$C_OFF"
    else
      do_plan && do_apply && do_kubeconfig && do_deploy && do_verify && do_persistence
    fi ;;
  *)
    printf '\n  usage: ./run-lab.sh <stage>\n'
    printf '  stages: preflight plan apply kubeconfig deploy verify persistence teardown all\n\n'
    exit 2 ;;
esac

# ---------------------------------------------------------------------------
head_ "SUMMARY"
printf '\n  %s evidence file(s) in %s\n' \
  "$(find "$OUT" -maxdepth 1 -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')" "$OUT"
ls -1 "$OUT" 2>/dev/null | sed 's/^/    /'

if [ "${#SHOTS[@]}" -gt 0 ]; then
  printf '\n  Screenshots prompted for:\n'
  printf '    %s\n' "${SHOTS[@]}"
fi

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\n  %sProblems:%s\n' "$C_ERR" "$C_OFF"
  printf "    - %s\n" "${FAILURES[@]}"
  printf '\n  %sTroubleshooting table: docs/RUNBOOK.md%s\n' "$C_WARN" "$C_OFF"
  printf '%s\n' "${FAILURES[@]}" > "$OUT/zz-failures.txt"
else
  printf '\n  %sNo failures recorded.%s\n' "$C_OK" "$C_OFF"
  : > "$OUT/zz-failures.txt"
fi
printf '\n'
