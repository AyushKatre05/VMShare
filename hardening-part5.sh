#!/usr/bin/env bash
# hardening-part5.sh
# Starter - SSH & Login Banner Hardening

set -euo pipefail
LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 5 Started ====="

SSHD="/etc/ssh/sshd_config"

backup() {
  cp -p "$1" "$1.bak.$(date +%F-%H%M%S)"
}

set_cfg() {
  local key="$1" val="$2"
  if grep -qE "^[# ]*${key}\b" "$SSHD"; then
    sed -i -E "s|^[# ]*${key}.*|${key} ${val}|" "$SSHD"
  else
    echo "${key} ${val}" >> "$SSHD"
  fi
}

backup "$SSHD"

set_cfg PermitRootLogin no
set_cfg Protocol 2
set_cfg X11Forwarding no
set_cfg MaxAuthTries 4
set_cfg LoginGraceTime 60
set_cfg ClientAliveInterval 300
set_cfg ClientAliveCountMax 0

cat >/etc/issue <<'EOF'
Authorized uses only. All activity may be monitored and reported.
EOF

cp /etc/issue /etc/issue.net

systemctl restart sshd || systemctl restart ssh || true

echo "Current SSH settings:"
sshd -T | egrep 'permitrootlogin|maxauthtries|x11forwarding|logingracetime|clientalive'

echo "===== Hardening Part 5 Completed ====="
