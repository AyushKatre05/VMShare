#!/usr/bin/env bash
set -euo pipefail
LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 2 Started ====="

cp -p /etc/fstab /etc/fstab.bak.$(date +%F-%H%M%S)

ensure_option() {
  mp="$1"; opt="$2"
  if grep -E "[[:space:]]${mp}[[:space:]]" /etc/fstab >/dev/null; then
    if ! grep -E "[[:space:]]${mp}[[:space:]].*${opt}" /etc/fstab >/dev/null; then
      sed -i -E "/[[:space:]]${mp}[[:space:]]/ s/defaults/defaults,${opt}/" /etc/fstab
      echo "Added ${opt} to ${mp}"
    else
      echo "${mp}: ${opt} already present"
    fi
  else
    echo "${mp} not found in /etc/fstab (manual review)"
  fi
}

ensure_option "/tmp" "nodev"
ensure_option "/tmp" "nosuid"
ensure_option "/tmp" "noexec"
ensure_option "/dev/shm" "nodev"
ensure_option "/dev/shm" "nosuid"
ensure_option "/dev/shm" "noexec"
ensure_option "/var/tmp" "nodev"
ensure_option "/var/tmp" "nosuid"

echo "Run 'mount -a' and verify mounts."
echo "===== Hardening Part 2 Complete ====="
