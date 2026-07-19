#!/usr/bin/env bash
# hardening-part4.sh
# UBI RHEL9 SCD - Part 4 (Additional Process Hardening & Crypto Policy - starter)

set -euo pipefail

LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 4 Started ====="

echo "[1] Configure ASLR"
cat >/etc/sysctl.d/99-hardening.conf <<EOF
kernel.randomize_va_space = 2
EOF

echo "[2] Disable core dumps"
cat >/etc/security/limits.d/99-hardening.conf <<EOF
* hard core 0
EOF

echo "fs.suid_dumpable = 0" >/etc/sysctl.d/99-coredump.conf

echo "[3] Apply sysctl settings"
sysctl --system || true

echo "[4] Configure system crypto policy"
if command -v update-crypto-policies >/dev/null 2>&1; then
    update-crypto-policies --set DEFAULT
    update-crypto-policies --show
else
    echo "update-crypto-policies not available."
fi

echo
echo "Verification:"
sysctl kernel.randomize_va_space || true
sysctl fs.suid_dumpable || true

echo "===== Hardening Part 4 Completed ====="
