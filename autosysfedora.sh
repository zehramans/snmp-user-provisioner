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

chage -M 365 devops

# ==========================================
# INSTALL PASSWORD QUALITY PACKAGE
# ==========================================
echo "=== Installing libpwquality ==="

dnf install -y libpwquality

# ==========================================
# CONFIGURE PASSWORD POLICY
# ==========================================
PWQUALITY="/etc/security/pwquality.conf"

cp "$PWQUALITY" "${PWQUALITY}.backup.$(date +%F-%H%M%S)"

sed -i '/^minlen/d' "$PWQUALITY"
sed -i '/^ucredit/d' "$PWQUALITY"
sed -i '/^lcredit/d' "$PWQUALITY"
sed -i '/^dcredit/d' "$PWQUALITY"
sed -i '/^ocredit/d' "$PWQUALITY"

cat >> "$PWQUALITY" <<EOF

# Company Password Policy
minlen = 10
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1
EOF

# ==========================================
# ENFORCE FOR ROOT
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
if [ -f /etc/snmp/snmpd.conf ]; then
    cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup
fi

# ==========================================
# CREATE SNMP CONFIG
# ==========================================
cat > /etc/snmp/snmpd.conf <<'EOF'

############################################################
# PASTE YOUR SNMP CONFIG BELOW
############################################################

# Example:
#
# agentAddress udp:161
# rocommunity public
#
# Replace with your actual configuration.

############################################################
# END OF SNMP CONFIG
############################################################

EOF

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
