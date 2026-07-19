#!/usr/bin/env bash
# hardening-part1.sh
# UBI RHEL 9 SCD - Part 1 (Initial Setup - Filesystem Kernel Modules)
# Generated for AlmaLinux/RHEL9 testing

set -euo pipefail

LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

echo "===== RHEL9 Hardening Part 1 Started ====="

MODULES=(
cramfs
freevxfs
hfs
hfsplus
jffs2
squashfs
udf
usb-storage
)

disable_module() {
    local mod="$1"
    echo "--- Processing $mod ---"

    cat >/etc/modprobe.d/${mod}.conf <<EOF
install ${mod} /bin/false
blacklist ${mod}
EOF

    if lsmod | grep -q "^${mod}\b"; then
        modprobe -r "$mod" || true
        rmmod "$mod" || true
    fi

    echo "$mod completed."
}

for m in "${MODULES[@]}"; do
    disable_module "$m"
done

echo "Checking SELinux..."
if command -v getenforce >/dev/null 2>&1; then
    getenforce
fi

echo "Installed disabled module configs:"
ls -1 /etc/modprobe.d/

echo "===== Hardening Part 1 Complete ====="
