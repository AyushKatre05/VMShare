#!/usr/bin/env bash
# hardening-part8.sh
# Starter - User Accounts & Password Policy

set -euo pipefail

LOG="/var/log/hardening.log"
exec > >(tee -a "$LOG") 2>&1

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "===== Hardening Part 8 Started ====="

echo "[1] Configure password aging"
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs || true
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs || true
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs || true

echo "[2] Lock inactive accounts after 30 days"
useradd -D -f 30 || true

echo "[3] List accounts with empty passwords"
awk -F: '($2==""){print $1}' /etc/shadow || true

echo "[4] List interactive users"
awk -F: '$7 !~ /(nologin|false)$/ {print $1":"$7}' /etc/passwd

echo "[5] Show password aging for root"
chage -l root || true

echo "===== Hardening Part 8 Completed ====="
