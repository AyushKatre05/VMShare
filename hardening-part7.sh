#!/usr/bin/env bash
# hardening-part7.sh
# Starter - System Maintenance & File Permissions

set -euo pipefail
LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 7 Started ====="

echo "[1] Correct permissions"
chmod 644 /etc/passwd || true
chmod 000 /etc/shadow || true
chmod 644 /etc/group || true
chown root:root /etc/passwd /etc/group /etc/shadow || true

echo "[2] Find world writable files"
find / -xdev -type f -perm -0002 2>/dev/null | tee /tmp/world_writable_files.txt

echo "[3] Find files without owner/group"
find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | tee /tmp/orphan_files.txt

echo "[4] Verify root PATH"
echo "$PATH"

echo "[5] Display UID 0 accounts"
awk -F: '($3==0){print $1}' /etc/passwd

echo "Reports:"
echo "/tmp/world_writable_files.txt"
echo "/tmp/orphan_files.txt"

echo "===== Hardening Part 7 Completed ====="
