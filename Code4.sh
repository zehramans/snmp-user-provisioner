#!/usr/bin/env bash

set -u

# ============================================================
# CONFIGURATION
# ============================================================

IP_FILE="ips.txt"
PASSWORD_FILE="new_passwords.txt"

SSH_USER="YOUR_USERNAME"
SSH_PASSWORD=""


# ============================================================
# DEBIAN / UBUNTU SETUP SCRIPT
# ============================================================

SCRIPT_DEBIAN=$(cat <<'SCRIPT_EOF'
#!/usr/bin/env bash

set -e

echo
echo "========================================"
echo "DEBIAN / UBUNTU CONFIGURATION"
echo "========================================"


# ============================================================
# ROOT CHECK
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must run as root."
    exit 1
fi


# ============================================================
# READ SYSADMIN PASSWORD
# ============================================================

PASSWORD_FILE="/tmp/.deployment_password"

if [[ ! -f "$PASSWORD_FILE" ]]; then
    echo "ERROR: Deployment password file not found."
    exit 1
fi

NEW_USER_PASSWORD=$(cat "$PASSWORD_FILE")

# Delete immediately after reading.
rm -f "$PASSWORD_FILE"

if [[ -z "$NEW_USER_PASSWORD" ]]; then
    echo "ERROR: sysadmin password is empty."
    exit 1
fi


# ============================================================
# CREATE SYSADMIN
# ============================================================

echo "=== Creating sysadmin user ==="

if id "sysadmin" &>/dev/null; then

    echo "User sysadmin already exists."

else

    useradd -m -s /bin/bash sysadmin

    echo "User sysadmin created."

fi


# ============================================================
# SET SYSADMIN PASSWORD
# ============================================================

echo "=== Setting sysadmin password ==="

echo "sysadmin:$NEW_USER_PASSWORD" | chpasswd

unset NEW_USER_PASSWORD

echo "Password configured successfully."


# ============================================================
# ADD SYSADMIN TO SUDO
# ============================================================

echo "=== Adding sysadmin to sudo group ==="

usermod -aG sudo sysadmin


# ============================================================
# PASSWORD EXPIRATION
# ============================================================

echo "=== Setting password expiration ==="

chage -M 365 sysadmin


# ============================================================
# INSTALL PASSWORD QUALITY MODULE
# ============================================================

echo "=== Installing libpam-pwquality ==="

apt-get update
apt-get install -y libpam-pwquality


# ============================================================
# CONFIGURE PASSWORD POLICY
# ============================================================

echo "=== Configuring password quality ==="

PWQUALITY="/etc/security/pwquality.conf"

if [[ -f "$PWQUALITY" ]]; then

    cp \
        "$PWQUALITY" \
        "${PWQUALITY}.backup.$(date +%F-%H%M%S)"

fi


sed -i '/^[[:space:]]*minlen[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ucredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*lcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*dcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ocredit[[:space:]]*=/d' "$PWQUALITY"


cat >> "$PWQUALITY" <<'PWEOF'

# Company Password Policy
minlen = 10
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1

PWEOF


# ============================================================
# PAM CONFIGURATION
# ============================================================

echo "=== Configuring PAM ==="

PAM_FILE="/etc/pam.d/common-password"

if [[ -f "$PAM_FILE" ]]; then

    cp \
        "$PAM_FILE" \
        "${PAM_FILE}.backup.$(date +%F-%H%M%S)"

    if grep -q "pam_pwquality.so" "$PAM_FILE"; then

        if ! grep "pam_pwquality.so" "$PAM_FILE" |
            grep -q "enforce_for_root"; then

            sed -i \
                '/pam_pwquality\.so/s/$/ enforce_for_root/' \
                "$PAM_FILE"

        fi

    fi

fi


# ============================================================
# INSTALL SNMPD
# ============================================================

echo "=== Installing SNMPD ==="

apt-get install -y snmpd


# ============================================================
# BACKUP SNMP CONFIGURATION
# ============================================================

echo "=== Backing up SNMP configuration ==="

if [[ -f /etc/snmp/snmpd.conf ]]; then

    cp \
        /etc/snmp/snmpd.conf \
        "/etc/snmp/snmpd.conf.backup.$(date +%F-%H%M%S)"

fi


# ============================================================
# WRITE SNMP CONFIGURATION
# ============================================================

echo "=== Writing SNMP configuration ==="

cat > /etc/snmp/snmpd.conf <<'SNMPEOF'

# ============================================================
# PUT YOUR DEBIAN / UBUNTU SNMPD.CONF HERE
# ============================================================


SNMPEOF


# ============================================================
# ENABLE + RESTART SNMPD
# ============================================================

echo "=== Enabling SNMPD ==="

systemctl enable snmpd


echo "=== Restarting SNMPD ==="

systemctl restart snmpd


# ============================================================
# STATUS
# ============================================================

echo
echo "========================================"
echo "DEBIAN / UBUNTU SETUP COMPLETE"
echo "========================================"
echo

echo "sysadmin configured."
echo "Password policy configured."
echo "SNMPD installed and enabled."

echo
echo "SNMPD status:"
echo

systemctl --no-pager --full status snmpd

SCRIPT_EOF
)


# ============================================================
# FEDORA / RHEL SETUP SCRIPT
# ============================================================

SCRIPT_FEDORA=$(cat <<'SCRIPT_EOF'
#!/usr/bin/env bash

set -e

echo
echo "========================================"
echo "FEDORA / RHEL CONFIGURATION"
echo "========================================"


# ============================================================
# ROOT CHECK
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must run as root."
    exit 1
fi


# ============================================================
# READ SYSADMIN PASSWORD
# ============================================================

PASSWORD_FILE="/tmp/.deployment_password"

if [[ ! -f "$PASSWORD_FILE" ]]; then
    echo "ERROR: Deployment password file not found."
    exit 1
fi

NEW_USER_PASSWORD=$(cat "$PASSWORD_FILE")

rm -f "$PASSWORD_FILE"

if [[ -z "$NEW_USER_PASSWORD" ]]; then
    echo "ERROR: sysadmin password is empty."
    exit 1
fi


# ============================================================
# CREATE SYSADMIN
# ============================================================

echo "=== Creating sysadmin user ==="

if id "sysadmin" &>/dev/null; then

    echo "User sysadmin already exists."

else

    useradd -m -s /bin/bash sysadmin

    echo "User sysadmin created."

fi


# ============================================================
# SET SYSADMIN PASSWORD
# ============================================================

echo "=== Setting sysadmin password ==="

echo "sysadmin:$NEW_USER_PASSWORD" | chpasswd

unset NEW_USER_PASSWORD

echo "Password configured successfully."


# ============================================================
# ADD SYSADMIN TO WHEEL
# ============================================================

echo "=== Adding sysadmin to wheel group ==="

usermod -aG wheel sysadmin


# ============================================================
# PASSWORD EXPIRATION
# ============================================================

echo "=== Setting password expiration ==="

chage -M 365 sysadmin


# ============================================================
# PASSWORD QUALITY
# ============================================================

echo "=== Installing libpwquality ==="

dnf install -y libpwquality


PWQUALITY="/etc/security/pwquality.conf"

if [[ -f "$PWQUALITY" ]]; then

    cp \
        "$PWQUALITY" \
        "${PWQUALITY}.backup.$(date +%F-%H%M%S)"

fi


sed -i '/^[[:space:]]*minlen[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ucredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*lcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*dcredit[[:space:]]*=/d' "$PWQUALITY"
sed -i '/^[[:space:]]*ocredit[[:space:]]*=/d' "$PWQUALITY"


cat >> "$PWQUALITY" <<'PWEOF'

# Company Password Policy
minlen = 10
ucredit = -1
lcredit = -1
dcredit = -1
ocredit = -1

PWEOF


# ============================================================
# PAM
# ============================================================

echo "=== Configuring PAM ==="

PAM_FILE="/etc/pam.d/system-auth"

if [[ -f "$PAM_FILE" ]]; then

    cp \
        "$PAM_FILE" \
        "${PAM_FILE}.backup.$(date +%F-%H%M%S)"

    if grep -q "pam_pwquality.so" "$PAM_FILE"; then

        if ! grep "pam_pwquality.so" "$PAM_FILE" |
            grep -q "enforce_for_root"; then

            sed -i \
                '/pam_pwquality\.so/s/$/ enforce_for_root/' \
                "$PAM_FILE"

        fi

    fi

fi


# ============================================================
# INSTALL SNMP
# ============================================================

echo "=== Installing SNMP ==="

dnf install -y net-snmp net-snmp-utils


# ============================================================
# BACKUP SNMP CONFIGURATION
# ============================================================

echo "=== Backing up SNMP configuration ==="

if [[ -f /etc/snmp/snmpd.conf ]]; then

    cp \
        /etc/snmp/snmpd.conf \
        "/etc/snmp/snmpd.conf.backup.$(date +%F-%H%M%S)"

fi


# ============================================================
# WRITE SNMP CONFIGURATION
# ============================================================

echo "=== Writing SNMP configuration ==="

cat > /etc/snmp/snmpd.conf <<'SNMPEOF'

# ============================================================
# PUT YOUR FEDORA / RHEL SNMPD.CONF HERE
# ============================================================


SNMPEOF


# ============================================================
# ENABLE + RESTART SNMP
# ============================================================

echo "=== Enabling SNMPD ==="

systemctl enable snmpd


echo "=== Restarting SNMPD ==="

systemctl restart snmpd


# ============================================================
# FIREWALL
# ============================================================

if systemctl is-active --quiet firewalld; then

    echo "=== Configuring firewall ==="

    firewall-cmd --permanent --add-port=161/udp
    firewall-cmd --reload

fi


# ============================================================
# STATUS
# ============================================================

echo
echo "========================================"
echo "FEDORA / RHEL SETUP COMPLETE"
echo "========================================"
echo

echo "sysadmin configured."
echo "Password policy configured."
echo "SNMPD installed and enabled."

echo
echo "SNMPD status:"
echo

systemctl --no-pager --full status snmpd

SCRIPT_EOF
)


# ============================================================
# LOCAL CHECKS
# ============================================================

if ! command -v sshpass >/dev/null 2>&1; then

    echo "ERROR: sshpass is not installed."
    exit 1

fi


if [[ ! -f "$IP_FILE" ]]; then

    echo "ERROR: $IP_FILE does not exist."
    exit 1

fi


if [[ ! -f "$PASSWORD_FILE" ]]; then

    echo "ERROR: $PASSWORD_FILE does not exist."
    exit 1

fi


# ============================================================
# GET SSH PASSWORD
# ============================================================

if [[ -z "$SSH_PASSWORD" ]]; then

    read -rsp "SSH password for $SSH_USER: " SSH_PASSWORD
    echo

fi


# ============================================================
# SSH OPTIONS
# ============================================================

SSH_OPTIONS=(
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=accept-new
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
)


# ============================================================
# LOAD SYSADMIN PASSWORDS
# ============================================================

declare -A NEW_PASSWORDS

while IFS='|' read -r PASSWORD_IP PASSWORD_VALUE; do

    PASSWORD_IP="${PASSWORD_IP//$'\r'/}"
    PASSWORD_VALUE="${PASSWORD_VALUE//$'\r'/}"

    [[ -z "$PASSWORD_IP" ]] && continue
    [[ "$PASSWORD_IP" == \#* ]] && continue

    NEW_PASSWORDS["$PASSWORD_IP"]="$PASSWORD_VALUE"

done < "$PASSWORD_FILE"


# ============================================================
# RESULTS
# ============================================================

SUCCESSFUL_IPS=()
FAILED_IPS=()


# ============================================================
# PROCESS SERVERS
# ============================================================

while IFS= read -r IP || [[ -n "$IP" ]]; do

    IP="${IP//$'\r'/}"

    [[ -z "$IP" ]] && continue
    [[ "$IP" == \#* ]] && continue


    echo
    echo "================================================"
    echo "PROCESSING: $IP"
    echo "================================================"


    # ========================================================
    # GET SYSADMIN PASSWORD FOR THIS SERVER
    # ========================================================

    NEW_USER_PASSWORD="${NEW_PASSWORDS[$IP]:-}"

    if [[ -z "$NEW_USER_PASSWORD" ]]; then

        echo "FATAL ERROR:"
        echo "No sysadmin password configured for $IP"

        exit 1

    fi


    # ========================================================
    # TEST SSH
    # ========================================================

    echo "[1/5] Testing SSH..."

    if ! sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'true' >/dev/null 2>&1
    then

        echo "SSH FAILED: $IP"

        FAILED_IPS+=("$IP")

        continue

    fi

    echo "SSH OK"


    # ========================================================
    # DETECT OS
    # ========================================================

    echo "[2/5] Detecting operating system..."

    OS_ID=$(
        sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        '. /etc/os-release 2>/dev/null &&
         printf "%s" "$ID"'
    )

    OS_ID="${OS_ID//$'\r'/}"

    echo "Detected: $OS_ID"


    # ========================================================
    # SELECT SCRIPT
    # ========================================================

    echo "[3/5] Selecting setup script..."

    case "$OS_ID" in

        ubuntu|debian)

            SELECTED_SCRIPT="$SCRIPT_DEBIAN"
            SCRIPT_NAME="Debian/Ubuntu"
            ;;


        fedora|rhel|centos|rocky|almalinux)

            SELECTED_SCRIPT="$SCRIPT_FEDORA"
            SCRIPT_NAME="Fedora/RHEL"
            ;;


        *)

            echo
            echo "FATAL ERROR:"
            echo "Unsupported operating system."
            echo
            echo "IP: $IP"
            echo "OS: $OS_ID"

            exit 1
            ;;

    esac

    echo "Selected: $SCRIPT_NAME"


    # ========================================================
    # UPLOAD SETUP SCRIPT
    # ========================================================

    echo "[4/5] Uploading setup script..."

    if ! printf '%s\n' "$SELECTED_SCRIPT" |
        sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'cat > /tmp/deployment_script.sh &&
         chmod 700 /tmp/deployment_script.sh'
    then

        echo
        echo "FATAL ERROR:"
        echo "Could not upload setup script."
        echo "IP: $IP"

        exit 1

    fi


    # ========================================================
    # UPLOAD SYSADMIN PASSWORD
    # ========================================================

    echo "[5/5] Preparing sysadmin configuration..."

    if ! printf '%s\n' "$NEW_USER_PASSWORD" |
        sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'umask 077 &&
         cat > /tmp/.deployment_password &&
         chmod 600 /tmp/.deployment_password'
    then

        echo
        echo "FATAL ERROR:"
        echo "Could not prepare configuration on $IP"

        exit 1

    fi


    # ========================================================
    # RUN REMOTE SCRIPT AS ROOT
    # ========================================================

    echo
    echo "========================================"
    echo "REMOTE SUDO AUTHENTICATION"
    echo "========================================"
    echo
    echo "Server: $IP"
    echo "User:   $SSH_USER"
    echo
    echo "Enter the sudo password when prompted."
    echo


    sshpass -p "$SSH_PASSWORD" \
        ssh -tt "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'sudo /tmp/deployment_script.sh'

    STATUS=$?


    # ========================================================
    # CLEANUP
    # ========================================================

    sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'rm -f /tmp/deployment_script.sh
         rm -f /tmp/.deployment_password' \
        >/dev/null 2>&1


    # ========================================================
    # CHECK RESULT
    # ========================================================

    if [[ $STATUS -ne 0 ]]; then

        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "DEPLOYMENT FAILED"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo
        echo "IP:        $IP"
        echo "OS:        $OS_ID"
        echo "Script:    $SCRIPT_NAME"
        echo "Exit code: $STATUS"
        echo
        echo "Deployment stopped."

        exit "$STATUS"

    fi


    SUCCESSFUL_IPS+=("$IP")

    unset NEW_USER_PASSWORD

    echo
    echo "SUCCESS: $IP"

done < "$IP_FILE"


# ============================================================
# FINAL REPORT
# ============================================================

echo
echo
echo "================================================"
echo "DEPLOYMENT REPORT"
echo "================================================"


echo
echo "SUCCESSFUL:"
echo "----------------------------------------"

if [[ ${#SUCCESSFUL_IPS[@]} -eq 0 ]]; then

    echo "None"

else

    for IP in "${SUCCESSFUL_IPS[@]}"; do

        echo "$IP    sysadmin configured"

    done

fi


echo
echo "SSH CONNECTION FAILED:"
echo "----------------------------------------"

if [[ ${#FAILED_IPS[@]} -eq 0 ]]; then

    echo "None"

else

    for IP in "${FAILED_IPS[@]}"; do

        echo "$IP"

    done

fi


unset SSH_PASSWORD

echo
echo "================================================"
echo "Finished."
echo "================================================"
