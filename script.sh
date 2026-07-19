#!/bin/bash

set -euo pipefail

############################################
# VARIABLES
############################################

SCRIPT_NAME=$(basename "$0")
DATE=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)

LOG_DIR="/var/log/ubi_hardening"
LOG_FILE="${LOG_DIR}/hardening_${DATE}.log"

BACKUP_DIR="/var/backups/ubi_hardening/${DATE}"

mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

############################################
# COLORS
############################################

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"

############################################
# LOGGING
############################################

log_info() {

    echo -e "${GREEN}[INFO]${NC} $1"

    echo "[INFO] $(date) : $1" >> "$LOG_FILE"

}

log_warn() {

    echo -e "${YELLOW}[WARN]${NC} $1"

    echo "[WARN] $(date) : $1" >> "$LOG_FILE"

}

log_error() {

    echo -e "${RED}[ERROR]${NC} $1"

    echo "[ERROR] $(date) : $1" >> "$LOG_FILE"

}

############################################
# ROOT CHECK
############################################

check_root() {

    if [[ $EUID -ne 0 ]]; then

        log_error "Run this script as root."

        exit 1

    fi

}

############################################
# OS VALIDATION
############################################

validate_os() {

    if [[ ! -f /etc/redhat-release ]]; then

        log_error "This script supports only RHEL."

        exit 1

    fi

    if ! grep -q "release 9" /etc/redhat-release; then

        log_error "RHEL 9 is required."

        exit 1

    fi

    log_info "Operating System Verified."

}

############################################
# BACKUP FUNCTION
############################################

backup_file() {

    FILE="$1"

    if [[ -f "$FILE" ]]; then

        DEST="${BACKUP_DIR}${FILE}"

        mkdir -p "$(dirname "$DEST")"

        cp -p "$FILE" "$DEST"

        log_info "Backup created : $FILE"

    fi

}

############################################
# SERVICE CHECK
############################################

service_exists() {

    systemctl list-unit-files | grep -q "^$1"

}

############################################
# PACKAGE CHECK
############################################

package_installed() {

    rpm -q "$1" >/dev/null 2>&1

}

############################################
# COMMAND CHECK
############################################

command_exists() {

    command -v "$1" >/dev/null 2>&1

}

############################################
# MODPROBE CONFIGURATION
############################################

disable_kernel_module() {

    MODULE=$1

    CONFIG="/etc/modprobe.d/${MODULE}.conf"

    log_info "Checking kernel module : $MODULE"

    if modinfo "$MODULE" >/dev/null 2>&1
    then

        touch "$CONFIG"

        if ! grep -q "^install ${MODULE}" "$CONFIG" 2>/dev/null
        then
            echo "install ${MODULE} /bin/false" >> "$CONFIG"
        fi

        if ! grep -q "^blacklist ${MODULE}" "$CONFIG" 2>/dev/null
        then
            echo "blacklist ${MODULE}" >> "$CONFIG"
        fi

        modprobe -r "$MODULE" 2>/dev/null || true

        rmmod "$MODULE" 2>/dev/null || true

        log_info "$MODULE disabled."

    else

        log_info "$MODULE not present."

    fi

}

############################################
# FILESYSTEM HARDENING
############################################

filesystem_kernel_modules() {

    log_info "Applying Filesystem Kernel Module Hardening"

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

    for MODULE in "${MODULES[@]}"
    do

        disable_kernel_module "$MODULE"

    done

    log_info "Filesystem Module Hardening Completed"

}

###############################################################################
# BATCH 1 - PART 2
# Filesystem Partition Hardening
###############################################################################

############################################
# FSTAB UPDATE
############################################

update_fstab_options() {

    MOUNT_POINT="$1"
    REQUIRED_OPTIONS="$2"

    if ! grep -qE "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab
    then
        log_warn "$MOUNT_POINT not found in /etc/fstab"
        return
    fi

    backup_file "/etc/fstab"

    CURRENT_LINE=$(grep -E "[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab)

    CURRENT_OPTIONS=$(echo "$CURRENT_LINE" | awk '{print $4}')

    NEW_OPTIONS="$CURRENT_OPTIONS"

    IFS=',' read -ra OPTLIST <<< "$REQUIRED_OPTIONS"

    for OPT in "${OPTLIST[@]}"
    do
        if [[ ",${NEW_OPTIONS}," != *",${OPT},"* ]]
        then
            NEW_OPTIONS="${NEW_OPTIONS},${OPT}"
        fi
    done

    NEW_OPTIONS=$(echo "$NEW_OPTIONS" | tr ',' '\n' | sort -u | paste -sd "," -)

    sed -i "\|[[:space:]]${MOUNT_POINT}[[:space:]]| s|${CURRENT_OPTIONS}|${NEW_OPTIONS}|" /etc/fstab

    log_info "$MOUNT_POINT updated with ${NEW_OPTIONS}"

}

############################################
# REMOUNT
############################################

remount_partition() {

    MP="$1"

    if mountpoint -q "$MP"
    then
        mount -o remount "$MP" && \
        log_info "$MP remounted successfully" || \
        log_warn "Unable to remount $MP"
    else
        log_warn "$MP is not currently mounted"
    fi

}

############################################
# /tmp
############################################

configure_tmp() {

    log_info "Configuring /tmp"

    update_fstab_options "/tmp" "nodev,nosuid,noexec"

    remount_partition "/tmp"

}

############################################
# /dev/shm
############################################

configure_dev_shm() {

    log_info "Configuring /dev/shm"

    update_fstab_options "/dev/shm" "nodev,nosuid,noexec"

    remount_partition "/dev/shm"

}

############################################
# /home
############################################

configure_home() {

    log_info "Configuring /home"

    update_fstab_options "/home" "nodev"

    remount_partition "/home"

}

############################################
# /var
############################################

configure_var() {

    log_info "Configuring /var"

    update_fstab_options "/var" "nodev"

    remount_partition "/var"

}

############################################
# /var/tmp
############################################

configure_var_tmp() {

    log_info "Configuring /var/tmp"

    update_fstab_options "/var/tmp" "nodev,nosuid,noexec"

    remount_partition "/var/tmp"

}

############################################
# /var/log
############################################

configure_var_log() {

    log_info "Configuring /var/log"

    update_fstab_options "/var/log" "nodev,nosuid,noexec"

    remount_partition "/var/log"

}

############################################
# /var/log/audit
############################################

configure_var_log_audit() {

    log_info "Configuring /var/log/audit"

    update_fstab_options "/var/log/audit" "nodev,nosuid,noexec"

    remount_partition "/var/log/audit"

}

############################################
# FILESYSTEM PARTITION HARDENING
############################################

filesystem_partition_hardening() {

    log_info "Starting Filesystem Partition Hardening"

    configure_tmp

    configure_dev_shm

    configure_home

    configure_var

    configure_var_tmp

    configure_var_log

    configure_var_log_audit

    log_info "Filesystem Partition Hardening Completed"

}

###############################################################################
# BATCH 1 - PART 3A
# PACKAGE MANAGEMENT HARDENING
###############################################################################

############################################
# VERIFY GPG CHECK
############################################

enable_gpgcheck() {

    log_info "Configuring global GPG check"

    backup_file "/etc/dnf/dnf.conf"

    if grep -q "^gpgcheck=" /etc/dnf/dnf.conf
    then
        sed -i 's/^gpgcheck=.*/gpgcheck=1/' /etc/dnf/dnf.conf
    else
        echo "gpgcheck=1" >> /etc/dnf/dnf.conf
    fi

    log_info "Global gpgcheck enabled"

}

############################################
# VERIFY REPO GPG CHECK
############################################

enable_repo_gpgcheck() {

    log_info "Checking repository GPG configuration"

    for repo in /etc/yum.repos.d/*.repo
    do

        [[ -f "$repo" ]] || continue

        backup_file "$repo"

        if grep -q "^gpgcheck=" "$repo"
        then
            sed -i 's/^gpgcheck=.*/gpgcheck=1/g' "$repo"
        else
            echo "gpgcheck=1" >> "$repo"
        fi

        if grep -q "^repo_gpgcheck=" "$repo"
        then
            sed -i 's/^repo_gpgcheck=.*/repo_gpgcheck=1/g' "$repo"
        else
            echo "repo_gpgcheck=1" >> "$repo"
        fi

        log_info "$repo secured"

    done

}

############################################
# VERIFY GPG KEYS
############################################

verify_gpg_keys() {

    log_info "Installed GPG Keys"

    rpm -qa gpg-pubkey | while read key
    do
        rpm -qi "$key" >> "$LOG_FILE"
    done

}

############################################
# PACKAGE VERIFICATION
############################################

verify_installed_packages() {

    log_info "Running RPM verification"

    rpm -Va > "${LOG_DIR}/rpm_verify_${DATE}.log" || true

    log_info "RPM verification completed"

}

############################################
# CLEAN PACKAGE CACHE
############################################

clean_package_cache() {

    log_info "Cleaning DNF cache"

    dnf clean all

    rm -rf /var/cache/dnf/*

}

############################################
# UPDATE METADATA
############################################

refresh_metadata() {

    log_info "Refreshing repository metadata"

    dnf makecache -y

}

############################################
# SECURITY UPDATE
############################################

install_security_updates() {

    log_info "Checking security updates"

    dnf update --security -y || true

}

############################################
# REMOVE UNUSED PACKAGES
############################################

remove_unused_packages() {

    log_info "Removing unnecessary packages"

    PKGS=(

        telnet
        telnet-server
        rsh
        rsh-server
        ypbind
        tftp
        tftp-server

    )

    for pkg in "${PKGS[@]}"
    do

        if rpm -q "$pkg" >/dev/null 2>&1
        then

            dnf remove "$pkg" -y

            log_info "$pkg removed"

        fi

    done

}

############################################
# VERIFY REPOSITORIES
############################################

verify_enabled_repositories() {

    log_info "Enabled repositories"

    dnf repolist > "${LOG_DIR}/repositories_${DATE}.log"

}

############################################
# PACKAGE MANAGEMENT
############################################

package_management_hardening() {

    log_info "=================================="

    log_info "PACKAGE MANAGEMENT HARDENING"

    log_info "=================================="

    enable_gpgcheck

    enable_repo_gpgcheck

    verify_gpg_keys

    verify_enabled_repositories

    refresh_metadata

    verify_installed_packages

    clean_package_cache

    install_security_updates

    remove_unused_packages

    log_info "Package Management Hardening Completed"

}
###############################################################################
# BATCH 1 - PART 3B
# SELINUX HARDENING
###############################################################################

############################################
# INSTALL SELINUX PACKAGES
############################################

install_selinux_packages() {

    log_info "Checking SELinux packages"

    PACKAGES=(

        libselinux
        libselinux-utils
        policycoreutils
        policycoreutils-python-utils
        selinux-policy
        selinux-policy-targeted
        setools-console

    )

    for pkg in "${PACKAGES[@]}"
    do

        if ! rpm -q "$pkg" >/dev/null 2>&1
        then

            log_info "Installing $pkg"

            dnf install -y "$pkg"

        else

            log_info "$pkg already installed"

        fi

    done

}

############################################
# BACKUP SELINUX CONFIG
############################################

backup_selinux_config() {

    backup_file "/etc/selinux/config"

}

############################################
# VERIFY SELINUX STATUS
############################################

verify_selinux_status() {

    STATUS=$(getenforce 2>/dev/null || echo "Disabled")

    log_info "Current SELinux Status : $STATUS"

}

############################################
# ENABLE SELINUX
############################################

enable_selinux() {

    log_info "Configuring SELinux"

    if grep -q "^SELINUX=" /etc/selinux/config
    then

        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' \
        /etc/selinux/config

    else

        echo "SELINUX=enforcing" >> /etc/selinux/config

    fi

    if grep -q "^SELINUXTYPE=" /etc/selinux/config
    then

        sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' \
        /etc/selinux/config

    else

        echo "SELINUXTYPE=targeted" >> /etc/selinux/config

    fi

}

############################################
# SET ENFORCING MODE
############################################

set_enforcing_mode() {

    CURRENT=$(getenforce 2>/dev/null || true)

    if [[ "$CURRENT" != "Enforcing" ]]
    then

        log_info "Switching SELinux to Enforcing"

        setenforce 1 2>/dev/null || true

    fi

}

############################################
# VERIFY BOOTLOADER
############################################

verify_bootloader_parameters() {

    log_info "Checking GRUB kernel parameters"

    CMDLINE=$(cat /proc/cmdline)

    if echo "$CMDLINE" | grep -q "selinux=0"
    then

        log_warn "selinux=0 detected"

    fi

    if echo "$CMDLINE" | grep -q "enforcing=0"
    then

        log_warn "enforcing=0 detected"

    fi

}

############################################
# REMOVE DISABLED PARAMETERS
############################################

fix_grub_selinux() {

    FILE="/etc/default/grub"

    backup_file "$FILE"

    sed -i 's/ selinux=0//g' "$FILE"

    sed -i 's/ enforcing=0//g' "$FILE"

}

############################################
# REGENERATE GRUB
############################################

rebuild_grub() {

    if [[ -d /sys/firmware/efi ]]
    then

        grub2-mkconfig -o \
        /boot/efi/EFI/redhat/grub.cfg

    else

        grub2-mkconfig -o \
        /boot/grub2/grub.cfg

    fi

}

############################################
# RELABEL FILESYSTEM
############################################

schedule_relabel() {

    if [[ ! -f /.autorelabel ]]
    then

        touch /.autorelabel

        log_info "Filesystem relabel scheduled"

    fi

}

############################################
# DISPLAY SELINUX INFO
############################################

selinux_summary() {

    echo ""

    echo "========== SELINUX STATUS =========="

    sestatus

    echo ""

}

############################################
# MAIN SELINUX HARDENING
############################################

selinux_hardening() {

    log_info "===================================="

    log_info "SELINUX HARDENING"

    log_info "===================================="

    install_selinux_packages

    backup_selinux_config

    verify_selinux_status

    enable_selinux

    set_enforcing_mode

    verify_bootloader_parameters

    fix_grub_selinux

    rebuild_grub

    schedule_relabel

    selinux_summary

    log_info "SELinux Hardening Completed"

}
###############################################################################
# BATCH 1 - PART 3C
# System Wide Crypto Policy & Login Banner
###############################################################################

############################################
# Configure Crypto Policy
############################################

configure_crypto_policy() {

    log_info "Configuring system-wide crypto policy"

    if ! command -v update-crypto-policies >/dev/null 2>&1; then
        log_warn "update-crypto-policies command not found"
        return
    fi

    CURRENT=$(update-crypto-policies --show)

    log_info "Current Crypto Policy : ${CURRENT}"

    if [[ "${CURRENT}" != "DEFAULT" ]]; then
        update-crypto-policies --set DEFAULT
        log_info "Crypto policy changed to DEFAULT"
    else
        log_info "Crypto policy already DEFAULT"
    fi
}

############################################
# Configure MOTD
############################################

configure_motd() {

    backup_file "/etc/motd"

cat > /etc/motd <<'EOF'
************************************************************************
*                      AUTHORIZED ACCESS ONLY                           *
*                                                                      *
* This computer system is the property of the organization.            *
* Unauthorized access or use is prohibited and may be monitored.       *
*                                                                      *
* Disconnect immediately if you are not an authorized user.            *
************************************************************************
EOF

    chmod 644 /etc/motd

    log_info "/etc/motd configured"

}

############################################
# Configure /etc/issue
############################################

configure_issue() {

    backup_file "/etc/issue"

cat > /etc/issue <<'EOF'
Authorized users only.
Unauthorized access is prohibited.
EOF

    chmod 644 /etc/issue

    log_info "/etc/issue configured"

}

############################################
# Configure /etc/issue.net
############################################

configure_issue_net() {

    backup_file "/etc/issue.net"

cat > /etc/issue.net <<'EOF'
Authorized users only.
This system may be monitored.
EOF

    chmod 644 /etc/issue.net

    log_info "/etc/issue.net configured"

}

############################################
# Permissions
############################################

secure_banner_permissions() {

    chmod 644 /etc/motd
    chmod 644 /etc/issue
    chmod 644 /etc/issue.net

    chown root:root /etc/motd
    chown root:root /etc/issue
    chown root:root /etc/issue.net

    log_info "Banner permissions secured"

}

############################################
# Display Summary
############################################

banner_summary() {

    echo
    echo "===== Banner Files ====="
    ls -l /etc/motd
    ls -l /etc/issue
    ls -l /etc/issue.net
    echo
}

############################################
# Main Function
############################################

crypto_and_banner_hardening() {

    log_info "====================================="
    log_info "Crypto Policy & Banner Hardening"
    log_info "====================================="

    configure_crypto_policy

    configure_motd

    configure_issue

    configure_issue_net

    secure_banner_permissions

    banner_summary

    log_info "Crypto & Banner Hardening Completed"

}

###############################################################################
# BATCH 1 - PART 4
# GNOME DISPLAY MANAGER HARDENING (Public RHEL 9 Guidance)
###############################################################################

############################################
# Check GDM
############################################

gdm_installed() {

    rpm -q gdm >/dev/null 2>&1

}

############################################
# Disable User List
############################################

disable_gdm_userlist() {

    if ! gdm_installed
    then
        log_info "GDM not installed."
        return
    fi

    mkdir -p /etc/dconf/db/gdm.d

cat > /etc/dconf/db/gdm.d/00-login-screen <<EOF
[org/gnome/login-screen]
disable-user-list=true
EOF

    dconf update

    log_info "Disabled GDM user list."

}

############################################
# Disable Guest Login
############################################

disable_guest_login() {

    if ! gdm_installed
    then
        return
    fi

    mkdir -p /etc/dconf/db/gdm.d

    cat >> /etc/dconf/db/gdm.d/00-login-screen <<EOF

banner-message-enable=true
banner-message-text='Authorized users only.'
EOF

    dconf update

}

############################################
# Disable Automatic Login
############################################

disable_auto_login() {

    FILE="/etc/gdm/custom.conf"

    [[ -f "$FILE" ]] || return

    backup_file "$FILE"

    sed -i 's/^AutomaticLoginEnable=.*/AutomaticLoginEnable=False/' "$FILE"

    sed -i 's/^TimedLoginEnable=.*/TimedLoginEnable=False/' "$FILE"

}

############################################
# Main
############################################

gdm_hardening() {

    log_info "Applying GDM Hardening"

    disable_gdm_userlist

    disable_guest_login

    disable_auto_login

    log_info "GDM Hardening Completed"

}

###############################################################################
# BATCH 2 - PART 1
# SERVICES HARDENING
###############################################################################

############################################
# Disable Service
############################################

disable_service() {

    SERVICE="$1"

    if systemctl list-unit-files | grep -q "^${SERVICE}"
    then

        log_info "Disabling ${SERVICE}"

        systemctl stop "${SERVICE}" 2>/dev/null || true

        systemctl disable "${SERVICE}" 2>/dev/null || true

        systemctl mask "${SERVICE}" 2>/dev/null || true

    else

        log_info "${SERVICE} not installed."

    fi

}

############################################
# Enable Service
############################################

enable_service() {

    SERVICE="$1"

    if systemctl list-unit-files | grep -q "^${SERVICE}"
    then

        log_info "Enabling ${SERVICE}"

        systemctl enable "${SERVICE}"

        systemctl start "${SERVICE}"

    fi

}

############################################
# Remove Legacy Services
############################################

disable_legacy_services() {

    log_info "Disabling insecure legacy services"

    SERVICES=(

        telnet.socket
        rsh.socket
        rexec.socket
        rlogin.socket
        tftp.socket
        vsftpd.service
        ypbind.service
        rpcbind.service
        avahi-daemon.service
        cups.service

    )

    for SVC in "${SERVICES[@]}"
    do
        disable_service "$SVC"
    done

}

############################################
# Disable Bluetooth
############################################

disable_bluetooth() {

    disable_service bluetooth.service

}

############################################
# Enable SSH
############################################

enable_sshd() {

    enable_service sshd.service

}

############################################
# Verify Enabled Services
############################################

verify_services() {

    log_info "Saving enabled service list"

    systemctl list-unit-files --state=enabled \
    > "${LOG_DIR}/enabled_services_${DATE}.txt"

}

############################################
# Main Services Hardening
############################################

services_hardening() {

    log_info "======================================"
    log_info "SERVICES HARDENING"
    log_info "======================================"

    disable_legacy_services

    disable_bluetooth

    enable_sshd

    verify_services

    log_info "Services Hardening Completed"

}
###############################################################################
# BATCH 2 - PART 2
# TIME SYNCHRONIZATION (CHRONY)
###############################################################################

############################################
# Install Chrony
############################################

install_chrony() {

    log_info "Checking Chrony installation"

    if ! rpm -q chrony >/dev/null 2>&1
    then
        log_info "Installing chrony"

        dnf install -y chrony
    else
        log_info "Chrony already installed"
    fi

}

############################################
# Backup Configuration
############################################

backup_chrony_config() {

    backup_file "/etc/chrony.conf"

}

############################################
# Configure NTP Servers
############################################

configure_chrony() {

    log_info "Configuring chrony"

    cat > /etc/chrony.conf <<EOF
pool 2.rhel.pool.ntp.org iburst

driftfile /var/lib/chrony/drift

makestep 1.0 3

rtcsync

keyfile /etc/chrony.keys

leapsectz right/UTC

logdir /var/log/chrony
EOF

}

############################################
# Secure Permissions
############################################

secure_chrony_permissions() {

    chmod 644 /etc/chrony.conf

    chown root:root /etc/chrony.conf

}

############################################
# Enable Service
############################################

enable_chronyd() {

    systemctl enable chronyd

    systemctl restart chronyd

}

############################################
# Verify Service
############################################

verify_chronyd() {

    if systemctl is-active --quiet chronyd
    then
        log_info "chronyd is running"
    else
        log_warn "chronyd is NOT running"
    fi

}

############################################
# Verify Time Sources
############################################

verify_sources() {

    chronyc sources -v \
        > "${LOG_DIR}/chrony_sources_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# Verify Tracking
############################################

verify_tracking() {

    chronyc tracking \
        > "${LOG_DIR}/chrony_tracking_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# Display Status
############################################

chrony_summary() {

    echo

    echo "========== CHRONY STATUS =========="

    systemctl status chronyd --no-pager

    echo

}

############################################
# Main Function
############################################

chrony_hardening() {

    log_info "=================================="

    log_info "TIME SYNCHRONIZATION"

    log_info "=================================="

    install_chrony

    backup_chrony_config

    configure_chrony

    secure_chrony_permissions

    enable_chronyd

    verify_chronyd

    verify_sources

    verify_tracking

    chrony_summary

    log_info "Chrony Hardening Completed"

}

###############################################################################
# BATCH 2 - PART 3
# CRON & AT HARDENING
###############################################################################

############################################
# Install Cron Package
############################################

install_cronie() {

    log_info "Checking cronie package"

    if ! rpm -q cronie >/dev/null 2>&1
    then
        dnf install -y cronie
        log_info "cronie installed"
    else
        log_info "cronie already installed"
    fi

}

############################################
# Enable Cron Service
############################################

enable_crond() {

    systemctl enable crond

    systemctl restart crond

    if systemctl is-active --quiet crond
    then
        log_info "crond is running"
    else
        log_warn "crond failed to start"
    fi

}

############################################
# Secure cron.allow
############################################

configure_cron_allow() {

    touch /etc/cron.allow

    chown root:root /etc/cron.allow

    chmod 600 /etc/cron.allow

    rm -f /etc/cron.deny

    log_info "cron.allow configured"

}

############################################
# Secure at.allow
############################################

configure_at_allow() {

    touch /etc/at.allow

    chown root:root /etc/at.allow

    chmod 600 /etc/at.allow

    rm -f /etc/at.deny

    log_info "at.allow configured"

}

############################################
# Secure Crontab
############################################

secure_crontab() {

    FILE="/etc/crontab"

    [[ -f "$FILE" ]] || return

    chown root:root "$FILE"

    chmod 600 "$FILE"

}

############################################
# Secure Cron Directories
############################################

secure_cron_directory() {

    DIR="$1"

    if [[ -d "$DIR" ]]
    then

        chown root:root "$DIR"

        chmod 700 "$DIR"

    fi

}

############################################
# Secure All Cron Directories
############################################

secure_all_cron_directories() {

    DIRS=(

        /etc/cron.hourly
        /etc/cron.daily
        /etc/cron.weekly
        /etc/cron.monthly
        /etc/cron.d

    )

    for DIR in "${DIRS[@]}"
    do
        secure_cron_directory "$DIR"
    done

}

############################################
# Verify Ownership
############################################

verify_cron_permissions() {

    ls -ld /etc/cron* \
        > "${LOG_DIR}/cron_permissions_${DATE}.txt" \
        2>/dev/null

}

############################################
# Verify Active Jobs
############################################

verify_cron_jobs() {

    crontab -l \
        > "${LOG_DIR}/current_user_cron_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# Main Function
############################################

cron_hardening() {

    log_info "================================"

    log_info "CRON HARDENING"

    log_info "================================"

    install_cronie

    enable_crond

    configure_cron_allow

    configure_at_allow

    secure_crontab

    secure_all_cron_directories

    verify_cron_permissions

    verify_cron_jobs

    log_info "Cron Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 1
# NETWORK KERNEL PARAMETER HARDENING
###############################################################################

############################################
# SYSCTL CONFIGURATION FILE
############################################

SYSCTL_FILE="/etc/sysctl.d/99-hardening.conf"

############################################
# BACKUP
############################################

backup_sysctl() {

    if [[ -f "$SYSCTL_FILE" ]]
    then
        backup_file "$SYSCTL_FILE"
    fi

}

############################################
# ADD / UPDATE SYSCTL
############################################

set_sysctl_parameter() {

    PARAM="$1"
    VALUE="$2"

    if grep -q "^${PARAM}" "$SYSCTL_FILE" 2>/dev/null
    then
        sed -i "s|^${PARAM}.*|${PARAM} = ${VALUE}|" "$SYSCTL_FILE"
    else
        echo "${PARAM} = ${VALUE}" >> "$SYSCTL_FILE"
    fi

}

############################################
# IPV4 HARDENING
############################################

configure_ipv4() {

    log_info "Configuring IPv4 Kernel Parameters"

    set_sysctl_parameter net.ipv4.ip_forward 0
    set_sysctl_parameter net.ipv4.conf.all.send_redirects 0
    set_sysctl_parameter net.ipv4.conf.default.send_redirects 0
    set_sysctl_parameter net.ipv4.conf.all.accept_source_route 0
    set_sysctl_parameter net.ipv4.conf.default.accept_source_route 0
    set_sysctl_parameter net.ipv4.conf.all.accept_redirects 0
    set_sysctl_parameter net.ipv4.conf.default.accept_redirects 0
    set_sysctl_parameter net.ipv4.conf.all.secure_redirects 0
    set_sysctl_parameter net.ipv4.conf.default.secure_redirects 0
    set_sysctl_parameter net.ipv4.conf.all.log_martians 1
    set_sysctl_parameter net.ipv4.conf.default.log_martians 1
    set_sysctl_parameter net.ipv4.icmp_echo_ignore_broadcasts 1
    set_sysctl_parameter net.ipv4.icmp_ignore_bogus_error_responses 1
    set_sysctl_parameter net.ipv4.tcp_syncookies 1
    set_sysctl_parameter net.ipv4.conf.all.rp_filter 1
    set_sysctl_parameter net.ipv4.conf.default.rp_filter 1

}

############################################
# IPV6 HARDENING
############################################

configure_ipv6() {

    log_info "Configuring IPv6 Kernel Parameters"

    set_sysctl_parameter net.ipv6.conf.all.accept_redirects 0
    set_sysctl_parameter net.ipv6.conf.default.accept_redirects 0
    set_sysctl_parameter net.ipv6.conf.all.accept_source_route 0
    set_sysctl_parameter net.ipv6.conf.default.accept_source_route 0

}

############################################
# NETWORK SECURITY
############################################

configure_network_security() {

    log_info "Configuring Network Security"

    set_sysctl_parameter kernel.randomize_va_space 2
    set_sysctl_parameter fs.suid_dumpable 0

}

############################################
# APPLY SETTINGS
############################################

apply_sysctl() {

    sysctl --system

}

############################################
# VERIFY SETTINGS
############################################

verify_sysctl() {

    sysctl -a > "${LOG_DIR}/sysctl_after_hardening_${DATE}.txt"

}

############################################
# DISPLAY IMPORTANT VALUES
############################################

show_network_status() {

    echo
    echo "=============================="

    sysctl net.ipv4.ip_forward
    sysctl net.ipv4.tcp_syncookies
    sysctl net.ipv4.conf.all.rp_filter
    sysctl net.ipv4.conf.all.accept_redirects
    sysctl net.ipv6.conf.all.accept_redirects

    echo "=============================="
    echo

}

############################################
# MAIN FUNCTION
############################################

network_kernel_hardening() {

    log_info "========================================"

    log_info "NETWORK KERNEL HARDENING"

    log_info "========================================"

    backup_sysctl

    touch "$SYSCTL_FILE"

    configure_ipv4

    configure_ipv6

    configure_network_security

    apply_sysctl

    verify_sysctl

    show_network_status

    log_info "Network Kernel Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 2
# FIREWALLD HARDENING (Public RHEL 9 Guidance)
###############################################################################

############################################
# Install firewalld
############################################

install_firewalld() {

    log_info "Checking firewalld"

    if ! rpm -q firewalld >/dev/null 2>&1
    then
        dnf install -y firewalld
        log_info "firewalld installed"
    else
        log_info "firewalld already installed"
    fi

}

############################################
# Enable firewalld
############################################

enable_firewalld() {

    systemctl enable firewalld
    systemctl restart firewalld

    if systemctl is-active --quiet firewalld
    then
        log_info "firewalld is running"
    else
        log_error "firewalld failed to start"
    fi

}

############################################
# Set Default Zone
############################################

set_default_zone() {

    firewall-cmd --set-default-zone=public

    log_info "Default zone set to public"

}

############################################
# Allow SSH
############################################

allow_ssh() {

    firewall-cmd --permanent --add-service=ssh

    log_info "SSH allowed"

}

############################################
# Remove Common Unused Services
############################################

remove_unused_services() {

    SERVICES=(

        dhcpv6-client
        samba
        cockpit

    )

    for svc in "${SERVICES[@]}"
    do

        firewall-cmd --permanent \
            --remove-service="$svc" \
            >/dev/null 2>&1 || true

    done

}

############################################
# Enable Logging
############################################

enable_logging() {

    firewall-cmd --set-log-denied=unicast

    log_info "Firewall logging enabled"

}

############################################
# Reload Rules
############################################

reload_firewall() {

    firewall-cmd --reload

}

############################################
# Save Current Configuration
############################################

save_firewall_config() {

    firewall-cmd --list-all \
        > "${LOG_DIR}/firewalld_${DATE}.txt"

}

############################################
# Display Status
############################################

firewall_summary() {

    echo
    echo "========== FIREWALL STATUS =========="

    firewall-cmd --get-default-zone

    firewall-cmd --list-all

    echo

}

############################################
# Main Function
############################################

firewall_hardening() {

    log_info "==================================="

    log_info "FIREWALL HARDENING"

    log_info "==================================="

    install_firewalld

    enable_firewalld

    set_default_zone

    allow_ssh

    remove_unused_services

    enable_logging

    reload_firewall

    save_firewall_config

    firewall_summary

    log_info "Firewall Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 3
# SSH SERVER HARDENING (Public RHEL 9 Guidance)
###############################################################################

############################################
# SSH CONFIG
############################################

SSHD_CONFIG="/etc/ssh/sshd_config"

############################################
# INSTALL SSH SERVER
############################################

install_openssh_server() {

    if ! rpm -q openssh-server >/dev/null 2>&1
    then
        log_info "Installing OpenSSH Server"
        dnf install -y openssh-server
    else
        log_info "OpenSSH Server already installed"
    fi

}

############################################
# BACKUP CONFIG
############################################

backup_sshd_config() {

    backup_file "$SSHD_CONFIG"

}

############################################
# UPDATE PARAMETER
############################################

set_sshd_option() {

    KEY="$1"
    VALUE="$2"

    if grep -qE "^${KEY}[[:space:]]+" "$SSHD_CONFIG"
    then
        sed -i "s|^${KEY}.*|${KEY} ${VALUE}|" "$SSHD_CONFIG"
    else
        echo "${KEY} ${VALUE}" >> "$SSHD_CONFIG"
    fi

}

############################################
# BASIC SSH SETTINGS
############################################

configure_sshd() {

    log_info "Configuring SSH"

    set_sshd_option Protocol 2
    set_sshd_option PermitRootLogin no
    set_sshd_option MaxAuthTries 4
    set_sshd_option MaxSessions 10
    set_sshd_option LoginGraceTime 60
    set_sshd_option X11Forwarding no
    set_sshd_option IgnoreRhosts yes
    set_sshd_option HostbasedAuthentication no
    set_sshd_option PermitEmptyPasswords no
    set_sshd_option PermitUserEnvironment no
    set_sshd_option ClientAliveInterval 300
    set_sshd_option ClientAliveCountMax 3
    set_sshd_option LogLevel VERBOSE
    set_sshd_option Compression no

}

############################################
# VALIDATE CONFIGURATION
############################################

validate_sshd() {

    if sshd -t
    then
        log_info "sshd configuration validation successful"
    else
        log_error "sshd configuration validation failed"
        exit 1
    fi

}

############################################
# ENABLE SERVICE
############################################

restart_sshd() {

    systemctl enable sshd
    systemctl restart sshd

}

############################################
# VERIFY SERVICE
############################################

verify_sshd() {

    if systemctl is-active --quiet sshd
    then
        log_info "sshd service is running"
    else
        log_error "sshd service is not running"
    fi

}

############################################
# SAVE EFFECTIVE CONFIG
############################################

save_sshd_config() {

    sshd -T > "${LOG_DIR}/sshd_effective_config_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# SUMMARY
############################################

ssh_summary() {

    echo
    echo "========== SSH STATUS =========="

    systemctl status sshd --no-pager

    echo

}

############################################
# MAIN FUNCTION
############################################

ssh_hardening() {

    log_info "==================================="
    log_info "SSH SERVER HARDENING"
    log_info "==================================="

    install_openssh_server

    backup_sshd_config

    configure_sshd

    validate_sshd

    restart_sshd

    verify_sshd

    save_sshd_config

    ssh_summary

    log_info "SSH Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 4
# PASSWORD AGING & ACCOUNT POLICY
###############################################################################

############################################
# CONFIGURATION
############################################

LOGIN_DEFS="/etc/login.defs"

############################################
# BACKUP
############################################

backup_login_defs() {

    backup_file "$LOGIN_DEFS"

}

############################################
# UPDATE login.defs
############################################

set_login_defs() {

    KEY="$1"
    VALUE="$2"

    if grep -qE "^${KEY}[[:space:]]+" "$LOGIN_DEFS"
    then
        sed -i "s/^${KEY}.*/${KEY}    ${VALUE}/" "$LOGIN_DEFS"
    else
        echo "${KEY}    ${VALUE}" >> "$LOGIN_DEFS"
    fi

}

############################################
# PASSWORD AGING
############################################

configure_password_aging() {

    log_info "Configuring password aging"

    set_login_defs PASS_MAX_DAYS 90
    set_login_defs PASS_MIN_DAYS 1
    set_login_defs PASS_WARN_AGE 7
    set_login_defs UID_MIN 1000

}

############################################
# UPDATE EXISTING USERS
############################################

update_existing_users() {

    while IFS=: read -r USER _ UID _ _ HOME SHELL
    do
        if [[ "$UID" -ge 1000 ]] && [[ "$SHELL" != "/sbin/nologin" ]]
        then
            chage --maxdays 90 "$USER"
            chage --mindays 1 "$USER"
            chage --warndays 7 "$USER"
        fi
    done < /etc/passwd

}

############################################
# LOCK UNUSED SYSTEM ACCOUNTS
############################################

lock_system_accounts() {

    ACCOUNTS=(
        games
        lp
        news
        uucp
    )

    for USER in "${ACCOUNTS[@]}"
    do
        if id "$USER" >/dev/null 2>&1
        then
            usermod -L "$USER" 2>/dev/null || true
            log_info "Locked account: $USER"
        fi
    done

}

############################################
# VERIFY PASSWORD SETTINGS
############################################

verify_password_policy() {

    grep "^PASS_" "$LOGIN_DEFS" \
        > "${LOG_DIR}/password_policy_${DATE}.txt"

}

############################################
# SUMMARY
############################################

password_summary() {

    echo
    echo "========== PASSWORD POLICY =========="
    grep "^PASS_" "$LOGIN_DEFS"
    echo

}

############################################
# MAIN
############################################

password_policy_hardening() {

    log_info "===================================="
    log_info "PASSWORD POLICY HARDENING"
    log_info "===================================="

    backup_login_defs

    configure_password_aging

    update_existing_users

    lock_system_accounts

    verify_password_policy

    password_summary

    log_info "Password Policy Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 5
# AUDITD HARDENING
###############################################################################

############################################
# VARIABLES
############################################

AUDITD_CONF="/etc/audit/auditd.conf"

############################################
# BACKUP
############################################

backup_auditd_config() {

    backup_file "$AUDITD_CONF"

}

############################################
# INSTALL AUDITD
############################################

install_auditd() {

    if ! rpm -q audit >/dev/null 2>&1
    then
        log_info "Installing audit packages"

        dnf install -y audit audit-libs

    else

        log_info "Audit packages already installed"

    fi

}

############################################
# UPDATE auditd.conf
############################################

set_auditd_option() {

    KEY="$1"
    VALUE="$2"

    if grep -q "^${KEY}" "$AUDITD_CONF"
    then
        sed -i "s|^${KEY}.*|${KEY} = ${VALUE}|" "$AUDITD_CONF"
    else
        echo "${KEY} = ${VALUE}" >> "$AUDITD_CONF"
    fi

}

############################################
# CONFIGURE AUDITD
############################################

configure_auditd() {

    log_info "Configuring auditd"

    set_auditd_option max_log_file 100
    set_auditd_option num_logs 10
    set_auditd_option max_log_file_action ROTATE
    set_auditd_option space_left 200
    set_auditd_option action_mail_acct root
    set_auditd_option admin_space_left 100
    set_auditd_option admin_space_left_action SUSPEND
    set_auditd_option disk_full_action SUSPEND
    set_auditd_option disk_error_action SUSPEND

}

############################################
# ENABLE SERVICE
############################################

enable_auditd() {

    systemctl enable auditd

    systemctl restart auditd

}

############################################
# VERIFY SERVICE
############################################

verify_auditd() {

    if systemctl is-active --quiet auditd
    then
        log_info "auditd is running"
    else
        log_warn "auditd is not running"
    fi

}

############################################
# SAVE STATUS
############################################

save_audit_status() {

    auditctl -s \
        > "${LOG_DIR}/audit_status_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# LIST ACTIVE RULES
############################################

save_audit_rules() {

    auditctl -l \
        > "${LOG_DIR}/audit_rules_${DATE}.txt" \
        2>/dev/null || true

}

############################################
# SUMMARY
############################################

audit_summary() {

    echo
    echo "========== AUDITD =========="

    systemctl status auditd --no-pager

    echo

}

############################################
# MAIN
############################################

auditd_hardening() {

    log_info "=================================="

    log_info "AUDITD HARDENING"

    log_info "=================================="

    install_auditd

    backup_auditd_config

    configure_auditd

    enable_auditd

    verify_auditd

    save_audit_status

    save_audit_rules

    audit_summary

    log_info "Auditd Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 6
# RSYSLOG & JOURNALD HARDENING
###############################################################################

############################################
# VARIABLES
############################################

RSYSLOG_CONF="/etc/rsyslog.conf"
JOURNAL_CONF="/etc/systemd/journald.conf"

############################################
# BACKUP CONFIGURATION
############################################

backup_logging_configs() {

    backup_file "$RSYSLOG_CONF"
    backup_file "$JOURNAL_CONF"

}

############################################
# SET CONFIG OPTION
############################################

set_config_option() {

    FILE="$1"
    KEY="$2"
    VALUE="$3"

    if grep -qE "^#?${KEY}=" "$FILE"
    then
        sed -i "s|^#\?${KEY}=.*|${KEY}=${VALUE}|" "$FILE"
    else
        echo "${KEY}=${VALUE}" >> "$FILE"
    fi

}

############################################
# CONFIGURE JOURNALD
############################################

configure_journald() {

    log_info "Configuring systemd-journald"

    mkdir -p /var/log/journal

    set_config_option "$JOURNAL_CONF" Storage persistent
    set_config_option "$JOURNAL_CONF" Compress yes
    set_config_option "$JOURNAL_CONF" Seal yes
    set_config_option "$JOURNAL_CONF" ForwardToSyslog yes

}

############################################
# CONFIGURE RSYSLOG
############################################

configure_rsyslog() {

    log_info "Configuring rsyslog"

    grep -q '^module(load="imuxsock")' "$RSYSLOG_CONF" \
        || echo 'module(load="imuxsock")' >> "$RSYSLOG_CONF"

    grep -q '^module(load="imjournal")' "$RSYSLOG_CONF" \
        || echo 'module(load="imjournal") StateFile="imjournal.state"' \
        >> "$RSYSLOG_CONF"

}

############################################
# LOG DIRECTORY PERMISSIONS
############################################

secure_log_directory() {

    chown root:root /var/log
    chmod 755 /var/log

    find /var/log -type f -exec chmod 640 {} \; 2>/dev/null || true

}

############################################
# ENABLE SERVICES
############################################

restart_logging_services() {

    systemctl enable systemd-journald
    systemctl restart systemd-journald

    systemctl enable rsyslog
    systemctl restart rsyslog

}

############################################
# VERIFY SERVICES
############################################

verify_logging_services() {

    for SERVICE in rsyslog systemd-journald
    do
        if systemctl is-active --quiet "$SERVICE"
        then
            log_info "$SERVICE is running"
        else
            log_warn "$SERVICE is not running"
        fi
    done

}

############################################
# SAVE STATUS
############################################

save_logging_status() {

    systemctl status rsyslog --no-pager \
        > "${LOG_DIR}/rsyslog_status_${DATE}.txt" 2>&1

    journalctl --disk-usage \
        > "${LOG_DIR}/journal_usage_${DATE}.txt" 2>&1

}

############################################
# SUMMARY
############################################

logging_summary() {

    echo
    echo "========== LOGGING SERVICES =========="
    systemctl --no-pager --type=service \
        | grep -E 'rsyslog|systemd-journald'
    echo

}

############################################
# MAIN
############################################

logging_hardening() {

    log_info "======================================"
    log_info "LOGGING HARDENING"
    log_info "======================================"

    backup_logging_configs

    configure_journald

    configure_rsyslog

    secure_log_directory

    restart_logging_services

    verify_logging_services

    save_logging_status

    logging_summary

    log_info "Logging Hardening Completed"

}

###############################################################################
# BATCH 3 - PART 7
# FILE PERMISSION & OWNERSHIP AUDIT
###############################################################################

############################################
# VARIABLES
############################################

PERMISSION_REPORT="${LOG_DIR}/permission_audit_${DATE}.txt"

############################################
# START REPORT
############################################

start_permission_report() {

    echo "==========================================" > "$PERMISSION_REPORT"
    echo " RHEL 9 FILE PERMISSION AUDIT"             >> "$PERMISSION_REPORT"
    echo " Generated: $(date)"                      >> "$PERMISSION_REPORT"
    echo "==========================================" >> "$PERMISSION_REPORT"
    echo >> "$PERMISSION_REPORT"

}

############################################
# CRITICAL FILES
############################################

audit_system_files() {

    log_info "Auditing critical system files"

    for FILE in \
        /etc/passwd \
        /etc/shadow \
        /etc/group \
        /etc/gshadow \
        /etc/ssh/sshd_config
    do
        if [[ -e "$FILE" ]]
        then
            ls -l "$FILE" >> "$PERMISSION_REPORT"
        fi
    done

    echo >> "$PERMISSION_REPORT"

}

############################################
# WORLD WRITABLE FILES
############################################

find_world_writable() {

    log_info "Searching for world writable files"

    find / \
        -xdev \
        -type f \
        -perm -0002 \
        2>/dev/null \
        >> "$PERMISSION_REPORT"

    echo >> "$PERMISSION_REPORT"

}

############################################
# WORLD WRITABLE DIRECTORIES
############################################

find_world_writable_dirs() {

    log_info "Searching for world writable directories"

    find / \
        -xdev \
        -type d \
        -perm -0002 \
        2>/dev/null \
        >> "$PERMISSION_REPORT"

    echo >> "$PERMISSION_REPORT"

}

############################################
# SUID FILES
############################################

find_suid_files() {

    log_info "Collecting SUID files"

    find / \
        -xdev \
        -perm -4000 \
        -type f \
        2>/dev/null \
        >> "$PERMISSION_REPORT"

    echo >> "$PERMISSION_REPORT"

}

############################################
# SGID FILES
############################################

find_sgid_files() {

    log_info "Collecting SGID files"

    find / \
        -xdev \
        -perm -2000 \
        -type f \
        2>/dev/null \
        >> "$PERMISSION_REPORT"

    echo >> "$PERMISSION_REPORT"

}

############################################
# FILES WITHOUT OWNER
############################################

find_orphan_files() {

    log_info "Searching orphaned files"

    find / \
        -xdev \
        \( -nouser -o -nogroup \) \
        2>/dev/null \
        >> "$PERMISSION_REPORT"

    echo >> "$PERMISSION_REPORT"

}

############################################
# HOME DIRECTORY PERMISSIONS
############################################

audit_home_directories() {

    log_info "Checking home directory permissions"

    while IFS=: read -r USER _ UID _ _ HOME SHELL
    do
        if [[ "$UID" -ge 1000 ]] && [[ -d "$HOME" ]]
        then
            stat -c "%n %A %U:%G" "$HOME" \
                >> "$PERMISSION_REPORT"
        fi
    done < /etc/passwd

    echo >> "$PERMISSION_REPORT"

}

############################################
# SUMMARY
############################################

permission_summary() {

    log_info "Permission audit report saved"

    echo
    echo "Report:"
    echo "$PERMISSION_REPORT"
    echo

}

############################################
# MAIN
############################################

permission_audit() {

    log_info "=================================="
    log_info "FILE PERMISSION AUDIT"
    log_info "=================================="

    start_permission_report

    audit_system_files

    find_world_writable

    find_world_writable_dirs

    find_suid_files

    find_sgid_files

    find_orphan_files

    audit_home_directories

    permission_summary

}

###############################################################################
# SYSTEM INVENTORY REPORT
###############################################################################

SYSTEM_REPORT="${LOG_DIR}/system_inventory_${DATE}.txt"

system_inventory_report() {

    log_info "Generating system inventory report"

    {
        echo "====================================================="
        echo "          RHEL 9 SYSTEM INVENTORY REPORT"
        echo "====================================================="
        echo

        echo "Hostname:"
        hostname
        echo

        echo "Operating System:"
        cat /etc/redhat-release
        echo

        echo "Kernel:"
        uname -r
        echo

        echo "Uptime:"
        uptime
        echo

        echo "CPU:"
        lscpu
        echo

        echo "Memory:"
        free -h
        echo

        echo "Disk Usage:"
        df -h
        echo

        echo "Mounted File Systems:"
        mount
        echo

        echo "SELinux Status:"
        sestatus
        echo

        echo "Firewall:"
        firewall-cmd --state 2>/dev/null || echo "Not running"
        echo

        echo "Running Services:"
        systemctl list-units --type=service --state=running
        echo

        echo "Listening Ports:"
        ss -tulnp
        echo

        echo "Installed Packages:"
        rpm -qa | sort
        echo

        echo "Audit Status:"
        auditctl -s 2>/dev/null
        echo

        echo "Journal Disk Usage:"
        journalctl --disk-usage
        echo

    } > "$SYSTEM_REPORT"

    log_info "Inventory report saved to:"
    log_info "$SYSTEM_REPORT"

}

###############################################################################
# SECURITY VERIFICATION REPORT
###############################################################################

SECURITY_REPORT="${LOG_DIR}/security_verification_${DATE}.txt"

security_verification() {

    log_info "Generating security verification report"

    {
        echo "=================================================="
        echo "RHEL 9 SECURITY VERIFICATION REPORT"
        echo "Generated: $(date)"
        echo "=================================================="
        echo

        echo "========== SELINUX =========="
        sestatus 2>/dev/null
        echo

        echo "========== FIREWALL =========="
        firewall-cmd --state 2>/dev/null || echo "firewalld not available"
        firewall-cmd --list-all 2>/dev/null
        echo

        echo "========== SSH =========="
        systemctl is-enabled sshd 2>/dev/null
        systemctl is-active sshd 2>/dev/null
        echo

        echo "========== AUDITD =========="
        systemctl is-enabled auditd 2>/dev/null
        systemctl is-active auditd 2>/dev/null
        auditctl -s 2>/dev/null
        echo

        echo "========== CHRONY =========="
        systemctl is-active chronyd 2>/dev/null
        chronyc tracking 2>/dev/null
        echo

        echo "========== LOGGING =========="
        systemctl is-active rsyslog 2>/dev/null
        journalctl --disk-usage 2>/dev/null
        echo

        echo "========== PASSWORD POLICY =========="
        grep "^PASS_" /etc/login.defs 2>/dev/null
        echo

        echo "========== MOUNT OPTIONS =========="
        findmnt -o TARGET,OPTIONS
        echo

        echo "========== RUNNING SERVICES =========="
        systemctl list-units --type=service --state=running
        echo

        echo "========== LISTENING PORTS =========="
        ss -tuln
        echo

    } > "$SECURITY_REPORT"

    log_info "Security verification report saved:"
    log_info "$SECURITY_REPORT"

}

############################################
# MAIN
############################################

main() {

    check_root

    validate_os

    filesystem_kernel_modules

    filesystem_partition_hardening

    package_management_hardening

    selinux_hardening

    crypto_and_banner_hardening

    gdm_hardening

    services_hardening

    chrony_hardening

    cron_hardening

    network_kernel_hardening

    firewall_hardening

    ssh_hardening

    password_policy_hardening

    auditd_hardening

    logging_hardening

    permission_audit

    system_inventory_report

    security_verification
}

main "$@"