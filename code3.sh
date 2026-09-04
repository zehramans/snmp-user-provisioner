#!/usr/bin/env bash

# ============================================================
# CONFIGURATION
# ============================================================

IP_FILE="ips.txt"
PASSWORD_FILE="new_passwords.txt"

SSH_USER="your_username"

# Leave blank to be prompted when this script starts.
SSH_PASSWORD=""


# ============================================================
# DEBIAN / UBUNTU SCRIPT
# ============================================================
#
# Paste your Debian/Ubuntu script below.
#
# The password assigned to the current server is available as:
#
#     $NEW_USER_PASSWORD
#
# Example:
#     ./some-command "$NEW_USER_PASSWORD"
#
# ============================================================

SCRIPT_DEBIAN=$(cat <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -e

echo "Running Debian/Ubuntu configuration..."

if [[ -z "${NEW_USER_PASSWORD:-}" ]]; then
    echo "ERROR: NEW_USER_PASSWORD is missing."
    exit 1
fi

# ==========================================
# PASTE YOUR DEBIAN/UBUNTU SCRIPT HERE
# ==========================================

# Your password-changing logic can read:
#
# "$NEW_USER_PASSWORD"

SCRIPT_EOF
)


# ============================================================
# FEDORA / RHEL SCRIPT
# ============================================================

SCRIPT_FEDORA=$(cat <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -e

echo "Running Fedora/RHEL configuration..."

if [[ -z "${NEW_USER_PASSWORD:-}" ]]; then
    echo "ERROR: NEW_USER_PASSWORD is missing."
    exit 1
fi

# ==========================================
# PASTE YOUR FEDORA/RHEL SCRIPT HERE
# ==========================================

# Your password-changing logic can read:
#
# "$NEW_USER_PASSWORD"

SCRIPT_EOF
)


# ============================================================
# CHECK REQUIREMENTS
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
# ASK FOR SSH PASSWORD
# ============================================================

if [[ -z "$SSH_PASSWORD" ]]; then
    read -rsp "SSH password: " SSH_PASSWORD
    echo
fi


# ============================================================
# SSH SETTINGS
# ============================================================

SSH_OPTIONS=(
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=accept-new
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
)


# ============================================================
# RESULT ARRAYS
# ============================================================

SUCCESSFUL_IPS=()
FAILED_IPS=()


# ============================================================
# LOAD PASSWORDS
# ============================================================
#
# new_passwords.txt:
#
# 192.168.1.10|newPassword1
# 192.168.1.11|newPassword2
# 192.168.1.12|newPassword3
#
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
# PROCESS SERVERS
# ============================================================

while IFS= read -r IP || [[ -n "$IP" ]]; do

    IP="${IP//$'\r'/}"

    [[ -z "$IP" ]] && continue
    [[ "$IP" == \#* ]] && continue

    echo
    echo "================================================"
    echo "Processing $IP"
    echo "================================================"


    # --------------------------------------------------------
    # FIND PASSWORD FOR THIS SERVER
    # --------------------------------------------------------

    NEW_USER_PASSWORD="${NEW_PASSWORDS[$IP]:-}"

    if [[ -z "$NEW_USER_PASSWORD" ]]; then
        echo "FATAL ERROR:"
        echo "No new password configured for $IP"
        exit 1
    fi


    # --------------------------------------------------------
    # TEST SSH
    # --------------------------------------------------------

    echo "[1/4] Testing SSH connection..."

    if ! sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        "true" >/dev/null 2>&1
    then

        echo "SSH FAILED: $IP"

        FAILED_IPS+=("$IP")

        continue
    fi

    echo "SSH OK"


    # --------------------------------------------------------
    # DETECT OS
    # --------------------------------------------------------

    echo "[2/4] Detecting OS..."

    OS_ID=$(
        sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        '. /etc/os-release 2>/dev/null && printf "%s" "$ID"'
    )

    OS_ID="${OS_ID//$'\r'/}"

    echo "OS: $OS_ID"


    # --------------------------------------------------------
    # SELECT SCRIPT
    # --------------------------------------------------------

    echo "[3/4] Selecting configuration script..."

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
            echo "FATAL ERROR"
            echo "IP: $IP"
            echo "Unsupported OS: $OS_ID"
            exit 1

            ;;
    esac

    echo "Selected: $SCRIPT_NAME"


    # --------------------------------------------------------
    # UPLOAD SCRIPT
    # --------------------------------------------------------

    echo "[4/4] Uploading configuration..."

    printf '%s\n' "$SELECTED_SCRIPT" |
        sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'cat > /tmp/deployment_script.sh &&
         chmod 700 /tmp/deployment_script.sh'

    STATUS=$?

    if [[ $STATUS -ne 0 ]]; then

        echo
        echo "FATAL ERROR"
        echo "IP: $IP"
        echo "Could not upload deployment script."
        echo "Exit code: $STATUS"

        exit "$STATUS"
    fi


    # --------------------------------------------------------
    # EXECUTE
    # --------------------------------------------------------

    echo
    echo "Executing..."
    echo

    # Pass NEW_USER_PASSWORD through stdin to avoid putting
    # the plaintext password in the remote process arguments.

    REMOTE_OUTPUT=$(
        printf '%s\n' "$NEW_USER_PASSWORD" |
            sshpass -p "$SSH_PASSWORD" \
            ssh "${SSH_OPTIONS[@]}" \
            "$SSH_USER@$IP" \
            '
            IFS= read -r NEW_USER_PASSWORD
            export NEW_USER_PASSWORD

            /tmp/deployment_script.sh
            '
        2>&1
    )

    STATUS=$?

    # Show output from your configuration script.

    printf '%s\n' "$REMOTE_OUTPUT"


    # --------------------------------------------------------
    # CLEAN UP
    # --------------------------------------------------------

    sshpass -p "$SSH_PASSWORD" \
        ssh "${SSH_OPTIONS[@]}" \
        "$SSH_USER@$IP" \
        'rm -f /tmp/deployment_script.sh' \
        >/dev/null 2>&1


    # --------------------------------------------------------
    # CHECK RESULT
    # --------------------------------------------------------

    if [[ $STATUS -ne 0 ]]; then

        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "REMOTE SCRIPT FAILED"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo
        echo "IP:        $IP"
        echo "OS:        $OS_ID"
        echo "Script:    $SCRIPT_NAME"
        echo "Exit code: $STATUS"
        echo
        echo "Remote output:"
        echo "----------------------------------------"
        printf '%s\n' "$REMOTE_OUTPUT"
        echo "----------------------------------------"
        echo
        echo "Stopping deployment."

        exit "$STATUS"
    fi


    SUCCESSFUL_IPS+=("$IP")

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
        echo "$IP    password updated"
    done

fi


echo
echo "SSH FAILED:"
echo "----------------------------------------"

if [[ ${#FAILED_IPS[@]} -eq 0 ]]; then

    echo "None"

else

    for IP in "${FAILED_IPS[@]}"; do
        echo "$IP"
    done

fi


echo
echo "================================================"
echo "Deployment finished."
echo "================================================"

unset SSH_PASSWORD
unset NEW_USER_PASSWORD
