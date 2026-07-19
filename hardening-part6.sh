#!/usr/bin/env bash
# hardening-part6.sh
# Starter - Logging & Auditing

set -euo pipefail
LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 6 Started ====="

echo "[1] Ensure rsyslog installed"
dnf -y install rsyslog || true
systemctl enable --now rsyslog || true

echo "[2] Ensure audit installed"
dnf -y install audit audit-libs || true
systemctl enable --now auditd || true

echo "[3] Configure journald persistence"
mkdir -p /var/log/journal
sed -i 's/^#*Storage=.*/Storage=persistent/' /etc/systemd/journald.conf || true
systemctl restart systemd-journald || true

echo "[4] Basic audit rule"
cat >/etc/audit/rules.d/99-local.rules <<EOF
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
EOF

augenrules --load || true

echo "[5] Status"
systemctl is-active rsyslog || true
systemctl is-active auditd || true

echo "===== Hardening Part 6 Completed ====="
