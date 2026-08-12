#!/bin/bash
###############################################################################
# Week 2 - Lab 2 : cloud-init bootstrap for ejada-w2-dev-app
#
# Paste into: Create Instance -> Advanced options -> Management
#             -> Cloud-init script (Paste cloud-init script)
#
# Runs once, on first boot, as root. No SSH or bastion access required.
# Logs: /var/log/lab2-bootstrap.log  and  /var/log/cloud-init-output.log
###############################################################################
set -euxo pipefail
exec > >(tee -a /var/log/lab2-bootstrap.log) 2>&1

MOUNT_TARGET_IP="10.0.2.177"    # ejada-w2-dev-mt
EXPORT_PATH="/app"              # File Storage export
DOC_ROOT="/var/www/html"        # Apache DocumentRoot == the NFS mount
APP_PORT="80"

echo "===== 1. Install packages ====="
dnf install -y nfs-utils httpd

echo "===== 2. Mount the File Storage export at $DOC_ROOT ====="
mkdir -p "$DOC_ROOT"
if ! grep -q "$DOC_ROOT" /etc/fstab; then
  echo "$MOUNT_TARGET_IP:$EXPORT_PATH $DOC_ROOT nfs nosuid,resvport,_netdev,nofail 0 0" >> /etc/fstab
fi

# The mount target can take a moment to answer on a cold boot; retry rather
# than fail the whole bootstrap.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if mount "$DOC_ROOT"; then
    echo "Mounted on attempt $attempt"
    break
  fi
  echo "Mount attempt $attempt failed, retrying in 15s"
  sleep 15
done
mountpoint -q "$DOC_ROOT" || { echo "FATAL: File Storage did not mount"; exit 1; }

echo "===== 3. Seed the application files onto File Storage ====="
if [ ! -f "$DOC_ROOT/index.html" ]; then
  cat > "$DOC_ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Ejada Week 2 - Lab 2</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; display: grid;
           place-items: center; min-height: 100vh; background: #0f172a; color: #e2e8f0; }
    .card { background: #1e293b; padding: 2.5rem 3rem; border-radius: 14px;
            box-shadow: 0 10px 40px rgba(0,0,0,.4); max-width: 44rem; }
    h1 { margin-top: 0; color: #38bdf8; }
    code { background: #0f172a; padding: .15rem .4rem; border-radius: 4px; }
    dt { font-weight: 600; color: #94a3b8; margin-top: .75rem; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Ejada Week 2 &mdash; Lab 2</h1>
    <p>You reached this page through a <strong>public Application Load Balancer</strong>.
       The web server runs on a <strong>private compute instance with no public IP</strong>,
       and this file is served from <strong>OCI File Storage</strong> over NFS.</p>
    <dl>
      <dt>Request path</dt>
      <dd>Internet &rarr; Load Balancer (10.0.1.0/24) &rarr; Instance (10.0.2.0/24) &rarr; File Storage</dd>
      <dt>Served from</dt>
      <dd><code>/var/www/html</code>, an NFS mount of <code>10.0.2.177:/app</code></dd>
    </dl>
    <p><em>Ejada Egypt Summer Internship 2026 &mdash; Cloud Build track.</em></p>
  </div>
</body>
</html>
HTML
fi

# Cheap endpoint for the load balancer health check.
[ -f "$DOC_ROOT/health" ] || echo "ok" > "$DOC_ROOT/health"

chown -R apache:apache "$DOC_ROOT" || true

echo "===== 4. Allow Apache to read from an NFS mount (SELinux) ====="
setsebool -P httpd_use_nfs 1

echo "===== 5. Open the application port in the host firewall ====="
systemctl enable --now firewalld
firewall-cmd --permanent --add-port="$APP_PORT"/tcp
firewall-cmd --reload

echo "===== 6. Start Apache ====="
systemctl enable --now httpd
systemctl is-active httpd

echo "===== Bootstrap complete ====="
df -hT "$DOC_ROOT"
curl -sS -o /dev/null -w 'local check: HTTP %{http_code}\n' "http://127.0.0.1:$APP_PORT/"
