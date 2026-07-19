#!/usr/bin/env bash
# hardening-part3.sh
# UBI RHEL9 SCD - Part 3 (Package Management & SELinux Checks)

set -euo pipefail

LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 3 Started ====="

echo "[1] Refresh package metadata..."
dnf -y makecache || true

echo "[2] Checking for updates..."
dnf check-update || true

echo "[3] Verifying GPG check..."
grep -R "^gpgcheck" /etc/yum.repos.d/ || true

echo "[4] Checking SELinux status..."
if command -v getenforce >/dev/null; then
    STATUS=$(getenforce)
    echo "SELinux: $STATUS"
fi

CFG=/etc/selinux/config
if [ -f "$CFG" ]; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' "$CFG"
    sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' "$CFG"
    echo "Updated $CFG"
fi

echo
echo "Current SELinux configuration:"
grep '^SELINUX' "$CFG" || true

echo
echo "NOTE:"
echo "- Reboot is required if SELinux mode changed."
echo "- Review repositories and GPG settings manually if required."

echo "===== Hardening Part 3 Completed ====="
