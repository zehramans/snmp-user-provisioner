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
# 1. CREATE SYSADMIN USER
# ==========================================

echo "=== Creating sysadmin user ==="

if id "sysadmin" &>/dev/null; then
    echo "User sysadmin already exists."
else
    useradd -m -s /bin/bash sysadmin
    echo "User sysadmin created."
fi


# ==========================================
# 2. ASK FOR SYSADMIN PASSWORD
# ==========================================

while true; do
    read -s -p "Enter password for sysadmin: " SYSADMIN_PASSWORD
    echo
    read -s -p "Confirm password: " SYSADMIN_PASSWORD_CONFIRM
    echo

    if [ "$SYSADMIN_PASSWORD" = "$SYSADMIN_PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Try again."
    fi
done

echo "sysadmin:$SYSADMIN_PASSWORD" | chpasswd

# Remove password from variables afterwards
unset SYSADMIN_PASSWORD
unset SYSADMIN_PASSWORD_CONFIRM

echo "Password set successfully."


# ==========================================
# 3. ADD SYSADMIN TO SUDO GROUP
# ==========================================

echo "=== Adding sysadmin to sudo group ==="

usermod -aG sudo sysadmin


# ==========================================
# 4. PASSWORD EXPIRATION
# Maximum password age = 365 days
# ==========================================

echo "=== Setting password expiration ==="

chage -M 365 sysadmin


# ==========================================
# 5. INSTALL PASSWORD QUALITY MODULE
# ==========================================

echo "=== Installing libpam-pwquality ==="

apt update
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

############################################################
#                                                          #
#       PASTE YOUR snmpd.conf CONTENT BELOW THIS LINE       #
#                                                          #
############################################################


# Example:
#
# agentAddress udp:161
# rocommunity public
#
# DELETE THE EXAMPLE ABOVE AND PASTE YOUR CONFIG HERE.


############################################################
#                                                          #
#       END OF YOUR snmpd.conf CONTENT                      #
#                                                          #
############################################################

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
echo "sysadmin user configured."
echo "Password policy configured."
echo "SNMPD installed and enabled."
echo
echo "SNMPD status:"
echo

systemctl --no-pager --full status snmpd
