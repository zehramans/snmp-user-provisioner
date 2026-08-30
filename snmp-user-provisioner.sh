#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# SNMP Monitoring User Provisioning Script
# Ubuntu / Debian
# ============================================================

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/var/log/snmp-user-setup.log"

SNMP_PACKAGE="snmpd"
SNMP_CONFIG="/etc/snmp/snmpd.conf"
SNMP_BACKUP="/etc/snmp/snmpd.conf.backup.$(date +%Y%m%d_%H%M%S)"

MONITORING_GROUP="monitoring"
SNMP_WRAPPER="/usr/local/sbin/snmp-config"
SUDOERS_FILE="/etc/sudoers.d/monitoring-snmp"

# Default values
USERNAME=""
DESCRIPTION="User permitted to configure SNMP"
EXPIRATION_DATE=""
COMMUNITY="labpublic"
MANAGER_IP=""

# ============================================================
# Logging / error handling
# ============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_handler() {
    local exit_code=$?
    local line_number=$1

    echo
    echo "ERROR: Script failed."
    echo "Line: $line_number"
    echo "Exit code: $exit_code"
    echo "Command: ${BASH_COMMAND}"
    echo "Check: $LOG_FILE"
    echo

    exit "$exit_code"
}

trap 'error_handler $LINENO' ERR

# ============================================================
# Usage
# ============================================================

usage() {
    cat <<EOF

Usage:
    sudo $SCRIPT_NAME [OPTIONS]

Options:

    -u, --user USER
        Username to create.

    -e, --expire DATE
        Account expiration date.
        Format: YYYY-MM-DD

    -d, --description TEXT
        User description.

    -c, --community STRING
        SNMP community string.
        Default: labpublic

    -m, --manager-ip IP
        IP address allowed to query SNMP.

    -v, --verbose
        Enable verbose Bash execution.

    -h, --help
        Show this help.

Example:

    sudo $SCRIPT_NAME \\
        --user snmpadmin \\
        --expire 2026-12-31 \\
        --description "SNMP configuration administrator" \\
        --community labpublic \\
        --manager-ip 192.168.0.113 \\
        --verbose

EOF
}

# ============================================================
# Argument parsing
# ============================================================

while [[ $# -gt 0 ]]; do

    case "$1" in

        -u|--user)
            USERNAME="$2"
            shift 2
            ;;

        -e|--expire)
            EXPIRATION_DATE="$2"
            shift 2
            ;;

        -d|--description)
            DESCRIPTION="$2"
            shift 2
            ;;

        -c|--community)
            COMMUNITY="$2"
            shift 2
            ;;

        -m|--manager-ip)
            MANAGER_IP="$2"
            shift 2
            ;;

        -v|--verbose)
            set -x
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;

    esac

done

# ============================================================
# Validation
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    echo "Use: sudo $SCRIPT_NAME ..."
    exit 1
fi

if [[ -z "$USERNAME" ]]; then
    echo "ERROR: Username is required."
    usage
    exit 1
fi

if [[ -z "$EXPIRATION_DATE" ]]; then
    echo "ERROR: Expiration date is required."
    usage
    exit 1
fi

if [[ -z "$MANAGER_IP" ]]; then
    echo "ERROR: Manager IP address is required."
    usage
    exit 1
fi

# Validate username
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    echo "ERROR: Invalid username."
    exit 1
fi

# Validate expiration date
if ! date -d "$EXPIRATION_DATE" >/dev/null 2>&1; then
    echo "ERROR: Invalid expiration date: $EXPIRATION_DATE"
    exit 1
fi

# Validate IPv4 address
if [[ ! "$MANAGER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: Invalid manager IP: $MANAGER_IP"
    exit 1
fi

# ============================================================
# Start logging
# ============================================================

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log "Starting SNMP monitoring user setup."
log "Username: $USERNAME"
log "Expiration: $EXPIRATION_DATE"
log "Manager IP: $MANAGER_IP"

# ============================================================
# Install required packages
# ============================================================

if ! dpkg-query -W -f='${Status}' "$SNMP_PACKAGE" 2>/dev/null \
    | grep -q "install ok installed"; then

    log "SNMP package not installed."
    log "Installing $SNMP_PACKAGE..."

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$SNMP_PACKAGE"

else

    log "$SNMP_PACKAGE is already installed."

fi

# ============================================================
# Create monitoring group
# ============================================================

if ! getent group "$MONITORING_GROUP" >/dev/null; then

    log "Creating group: $MONITORING_GROUP"

    groupadd "$MONITORING_GROUP"

else

    log "Group $MONITORING_GROUP already exists."

fi

# ============================================================
# Create user
# ============================================================

if id "$USERNAME" >/dev/null 2>&1; then

    log "User $USERNAME already exists."

else

    log "Creating user: $USERNAME"

    useradd \
        --create-home \
        --shell /bin/bash \
        --comment "$DESCRIPTION" \
        "$USERNAME"

fi

# ============================================================
# Add user to monitoring group
# ============================================================

log "Adding $USERNAME to $MONITORING_GROUP."

usermod -aG "$MONITORING_GROUP" "$USERNAME"

# ============================================================
# Set account expiration
# ============================================================

log "Setting account expiration to $EXPIRATION_DATE."

usermod \
    --expiredate "$(date -d "$EXPIRATION_DATE" +%Y-%m-%d)" \
    "$USERNAME"

# ============================================================
# Configure SNMP
# ============================================================

if [[ -f "$SNMP_CONFIG" ]]; then

    log "Backing up existing SNMP configuration."

    cp -a "$SNMP_CONFIG" "$SNMP_BACKUP"

    log "Backup created: $SNMP_BACKUP"

fi

log "Creating SNMP configuration."

cat > "$SNMP_CONFIG" <<EOF
# ============================================================
# SNMP configuration
# Managed by provisioning script
# ============================================================

agentAddress udp:161

rocommunity $COMMUNITY $MANAGER_IP

sysLocation "Monitoring Lab"
sysContact "Monitoring Team"
EOF

chmod 600 "$SNMP_CONFIG"
chown root:root "$SNMP_CONFIG"

# ============================================================
# Create restricted SNMP management wrapper
# ============================================================

log "Creating restricted SNMP management wrapper."

cat > "$SNMP_WRAPPER" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG="/etc/snmp/snmpd.conf"

case "${1:-}" in

    status)
        systemctl status snmpd --no-pager
        ;;

    restart)
        systemctl restart snmpd
        ;;

    start)
        systemctl start snmpd
        ;;

    stop)
        systemctl stop snmpd
        ;;

    enable)
        systemctl enable snmpd
        ;;

    config)
        cat "$CONFIG"
        ;;

    *)
        echo "Usage:"
        echo "  snmp-config status"
        echo "  snmp-config restart"
        echo "  snmp-config start"
        echo "  snmp-config stop"
        echo "  snmp-config enable"
        echo "  snmp-config config"
        exit 1
        ;;

esac
EOF

chmod 755 "$SNMP_WRAPPER"
chown root:root "$SNMP_WRAPPER"

# ============================================================
# Configure restricted sudo permissions
# ============================================================

log "Creating restricted sudo rule."

cat > "$SUDOERS_FILE" <<EOF
# SNMP configuration permissions for $USERNAME
$USERNAME ALL=(root) $SNMP_WRAPPER
EOF

chmod 440 "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"

# Validate sudo configuration
visudo -cf "$SUDOERS_FILE"

# ============================================================
# Enable and start SNMP
# ============================================================

log "Enabling SNMP service."

systemctl enable snmpd

log "Restarting SNMP service."

systemctl restart snmpd

# ============================================================
# Validation
# ============================================================

log "Checking SNMP service status."

systemctl is-active --quiet snmpd

log "Checking UDP/161."

if ss -lun | grep -q ':161'; then
    log "SNMP is listening on UDP/161."
else
    log "WARNING: UDP/161 was not detected."
fi

log "Checking user."

id "$USERNAME"

log "Checking group membership."

if id -nG "$USERNAME" | grep -qw "$MONITORING_GROUP"; then
    log "User is a member of $MONITORING_GROUP."
else
    echo "ERROR: User was not added to $MONITORING_GROUP."
    exit 1
fi

log "Checking account expiration."

chage -l "$USERNAME"

log "Checking sudo configuration."

sudo -l -U "$USERNAME"

# ============================================================
# Completion
# ============================================================

echo
echo "============================================================"
echo " SNMP MONITORING USER SETUP COMPLETE"
echo "============================================================"
echo
echo "User:          $USERNAME"
echo "Group:         $MONITORING_GROUP"
echo "Expires:       $EXPIRATION_DATE"
echo "Description:   $DESCRIPTION"
echo "SNMP Package:  $SNMP_PACKAGE"
echo "SNMP Config:   $SNMP_CONFIG"
echo "Manager IP:    $MANAGER_IP"
echo "Community:     $COMMUNITY"
echo "Wrapper:       $SNMP_WRAPPER"
echo "Sudo Rule:     $SUDOERS_FILE"
echo "Log:           $LOG_FILE"
echo
echo "The user has restricted SNMP administration privileges."
echo
