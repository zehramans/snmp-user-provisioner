#!/bin/bash

set -e

# ==========================================
# Make sure script is being run as root
# ==========================================
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo:"
    echo "sudo ./setup.sh"
    exit 1
fi


# ==========================================
# 1. CREATE devops USER
# ==========================================

echo "=== Creating devops user ==="

if id "devops" &>/dev/null; then
    echo "User devops already exists."
else
    useradd -m -s /bin/bash devops
    echo "User devops created."
fi


# ==========================================
# 2. ASK FOR devops PASSWORD
# ==========================================

while true; do
    read -s -p "Enter password for devops: " devops_PASSWORD
    echo
    read -s -p "Confirm password: " devops_PASSWORD_CONFIRM
    echo

    if [ "$devops_PASSWORD" = "$devops_PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Try again."
    fi
done

echo "devops:$devops_PASSWORD" | chpasswd

# Remove password from variables afterwards
unset devops_PASSWORD
unset devops_PASSWORD_CONFIRM

echo "Password set successfully."


# ==========================================
# 3. ADD devops TO SUDO GROUP
# ==========================================

echo "=== Adding devops to sudo group ==="

usermod -aG sudo devops


# ==========================================
# 4. PASSWORD EXPIRATION
# Maximum password age = 365 days
# ==========================================




# ==========================================
# 5. INSTALL PASSWORD QUALITY MODULE
# ==========================================

echo "=== Installing libpam-pwquality ==="


apt install -y libpam-pwquality




# ==========================================
# 7. ENFORCE PASSWORD QUALITY FOR ROOT
# ==========================================

echo "=== Enforcing password quality for root ==="

PAM_FILE="/etc/pam.d/common-password"

cp "$PAM_FILE" "${PAM_FILE}.backup"

# Add enforce_for_root to the pam_pwquality line if not already present
if grep -q "pam_pwquality.so" "$PAM_FILE"; then
    if ! grep "pam_pwquality.so" "$PAM_FILE" | grep -q "enforce_for_root"; then
        sed -i '/pam_pwquality\.so/s/$/ enforce_for_root/' "$PAM_FILE"
    fi
fi


# ==========================================
# 8. INSTALL SNMPD
# ==========================================

echo "=== Installing SNMPD ==="

apt install -y snmpd


# ==========================================
# 9. BACK UP ORIGINAL SNMP CONFIG
# ==========================================

echo "=== Backing up SNMP configuration ==="

if [ -f /etc/snmp/snmpd.conf ]; then
    cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup
fi


# ==========================================
# 10. CREATE SNMP CONFIGURATION
# ==========================================

echo "=== Creating SNMP configuration ==="

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
# 11. ENABLE SNMPD
# ==========================================

echo "=== Enabling SNMPD ==="

systemctl enable snmpd


# ==========================================
# 12. RESTART SNMPD
# ==========================================

echo "=== Restarting SNMPD ==="

systemctl restart snmpd


# ==========================================
# 13. SHOW SNMPD STATUS
# ==========================================

echo
echo "=========================================="
echo "SETUP COMPLETE"
echo "=========================================="
echo
echo "devops user configured."
echo "Password policy configured."
echo "SNMPD installed and enabled."
echo
echo "SNMPD status:"
echo

systemctl --no-pager --full status snmpd

rm -- "$0"
