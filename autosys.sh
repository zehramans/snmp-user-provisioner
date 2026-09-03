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

echo "=== Setting password expiration ==="

chage -M 365 devops


# ==========================================
# 5. INSTALL PASSWORD QUALITY MODULE
# ==========================================

echo "=== Installing libpam-pwquality ==="


apt install -y libpam-pwquality


# ==========================================
# 6. CONFIGURE PASSWORD QUALITY
# ==========================================

echo "=== Configuring password quality ==="

PWQUALITY="/etc/security/pwquality.conf"

# Backup
cp "$PWQUALITY" "${PWQUALITY}.backup"

# Remove old versions of these settings
sed -i '/^[[:space:]]*minlen[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ucredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*lcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*dcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ocredit[[:space:]]*=/d' "$PWQUALITY"

cat >> "$PWQUALITY" <<'EOF'

# Password policy
minlen = 10
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
EOF


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

cat > /etc/snmp/snmpd.conf <<'EOF'



EOF


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
