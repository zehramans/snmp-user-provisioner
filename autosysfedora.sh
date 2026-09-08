#!/bin/bash

set -e

# ==========================================
# ROOT CHECK
# ==========================================
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "sudo ./setup.sh"
    exit 1
fi

# ==========================================
# CREATE USER
# ==========================================
echo "=== Creating devops user ==="

if id "devops" &>/dev/null; then
    echo "User devops already exists."
else
    useradd -m -s /bin/bash devops
fi

# ==========================================
# PASSWORD PROMPT
# ==========================================
while true; do
    read -s -p "Enter password for devops: " PASS1
    echo
    read -s -p "Confirm password: " PASS2
    echo

    if [ "$PASS1" = "$PASS2" ]; then
        break
    fi

    echo "Passwords do not match."
done

echo "devops:$PASS1" | chpasswd

unset PASS1
unset PASS2

# ==========================================
# ADD TO SUDO GROUP
# ==========================================
echo "=== Adding devops to wheel group ==="

usermod -aG wheel devops

# ==========================================
# PASSWORD EXPIRATION
# ==========================================
echo "=== Setting password expiration ==="

# ==========================================
# INSTALL PASSWORD QUALITY PACKAGE
# ==========================================
echo "=== Installing libpwquality ==="

dnf install -y libpwquality

# ==========================================
# CONFIGURE PASSWORD POLICY
# ==========================================

echo "=== Configuring PAM ==="

PAM_FILE="/etc/pam.d/system-auth"

cp "$PAM_FILE" "${PAM_FILE}.backup.$(date +%F-%H%M%S)"

if grep -q "pam_pwquality.so" "$PAM_FILE"; then
    if ! grep "pam_pwquality.so" "$PAM_FILE" | grep -q "enforce_for_root"; then
        sed -i '/pam_pwquality\.so/s/$/ enforce_for_root/' "$PAM_FILE"
    fi
fi

# ==========================================
# INSTALL SNMP
# ==========================================
echo "=== Installing SNMP ==="

dnf install -y net-snmp net-snmp-utils

# ==========================================
# BACKUP SNMP CONFIG
# ==========================================
# ============================================================
# SNMP CONFIGURATION CHECK
# ============================================================

SNMP_CONF="/etc/snmp/snmpd.conf"
SNMP_BACKUP="/snmpd.conf.backup"

if [[ -f "$SNMP_BACKUP" ]]; then
    echo "[OK] SNMP backup already exists."
    echo "[OK] Skipping SNMP configuration."

else
    echo "[!] $SNMP_BACKUP does not exist."
    echo "[!] SNMP configuration is required."
    echo
    echo "Paste the contents of snmpd.conf below."
    echo "When finished, type EOF on a new line and press Enter:"
    echo "------------------------------------------------------------"

    TMP_CONF=$(mktemp)

    while IFS= read -r line; do
        [[ "$line" == "EOF" ]] && break
        printf '%s\n' "$line" >> "$TMP_CONF"
    done

    # Make sure something was actually pasted
    if [[ ! -s "$TMP_CONF" ]]; then
        echo "ERROR: No SNMP configuration was provided."
        rm -f "$TMP_CONF"
        exit 1
    fi

    # Ensure SNMP directory exists
    sudo mkdir -p /etc/snmp

    # If an existing snmpd.conf exists, preserve it as the backup
    if [[ -f "$SNMP_CONF" ]]; then
        sudo cp "$SNMP_CONF" "$SNMP_BACKUP"
        echo "[OK] Existing configuration backed up to $SNMP_BACKUP"
    else
        # Create marker/backup file if no previous config existed
        sudo touch "$SNMP_BACKUP"
        echo "[OK] Created $SNMP_BACKUP"
    fi

    # Install the new configuration
    sudo install -o root -g root -m 600 "$TMP_CONF" "$SNMP_CONF"

    rm -f "$TMP_CONF"

    echo "[OK] New SNMP configuration written to:"
    echo "     $SNMP_CONF"
fi

echo "[OK] Continuing with the rest of the script..."

# ==========================================
# ENABLE & START SNMP
# ==========================================
echo "=== Enabling SNMP ==="

systemctl enable snmpd
systemctl restart snmpd

# ==========================================
# FIREWALL (OPTIONAL)
# ==========================================

if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=161/udp
    firewall-cmd --reload
fi

# ==========================================
# STATUS
# ==========================================
echo
echo "================================="
echo "SETUP COMPLETE"
echo "================================="
echo

systemctl --no-pager status snmpd

rm -- "$0"
