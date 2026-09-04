#!/usr/bin/env bash

set -u
set -o pipefail

# ==========================================================
# CONFIGURATION
# ==========================================================

USERNAME1="sysadmin"
USERNAME2="admin"

# ----------------------------------------------------------
# GitHub RAW links
#
# USERNAME1 + Ubuntu/Debian
SCRIPT_USER1_DEBIAN="https://raw.githubusercontent.com/USER/REPO/main/script1.sh"

# USERNAME2 + Ubuntu/Debian
SCRIPT_USER2_DEBIAN="https://raw.githubusercontent.com/USER/REPO/main/script2.sh"

# USERNAME1 + Fedora
SCRIPT_USER1_FEDORA="https://raw.githubusercontent.com/USER/REPO/main/script3.sh"

# USERNAME2 + Fedora
SCRIPT_USER2_FEDORA="https://raw.githubusercontent.com/USER/REPO/main/script4.sh"

# ==========================================================
# CHECK ARGUMENT
# ==========================================================

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 inventory.txt"
    echo
    echo "Inventory format:"
    echo "192.168.1.10,user1"
    echo "192.168.1.11,user2"
    exit 1
fi

INVENTORY="$1"

if [[ ! -f "$INVENTORY" ]]; then
    echo "ERROR: File not found: $INVENTORY"
    exit 1
fi

# ==========================================================
# CHECK SSHPASS
# ==========================================================

if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass is required."
    echo
    echo "Debian/Ubuntu:"
    echo "  sudo apt install sshpass"
    echo
    echo "Fedora:"
    echo "  sudo dnf install sshpass"
    exit 1
fi

# ==========================================================
# PASSWORDS
# ==========================================================

read -rsp "Password for $USERNAME1: " PASSWORD1
echo

read -rsp "Password for $USERNAME2: " PASSWORD2
echo

echo

# ==========================================================
# FAILED CONNECTION LIST
# ==========================================================

FAILED_CONNECTIONS=()

# ==========================================================
# PROCESS SERVERS
# ==========================================================

while IFS=',' read -r IP ACCOUNT; do

    # Remove spaces / CRLF characters
    IP=$(echo "$IP" | tr -d '\r' | xargs)
    ACCOUNT=$(echo "$ACCOUNT" | tr -d '\r' | xargs)

    # Ignore blank lines
    [[ -z "$IP" ]] && continue

    # Ignore comments
    [[ "$IP" =~ ^# ]] && continue

    echo
    echo "======================================================"
    echo "Processing: $IP"
    echo "======================================================"

    # ------------------------------------------------------
    # SELECT ACCOUNT
    # ------------------------------------------------------

    case "$ACCOUNT" in

        user1)
            USERNAME="$USERNAME1"
            PASSWORD="$PASSWORD1"
            ;;

        user2)
            USERNAME="$USERNAME2"
            PASSWORD="$PASSWORD2"
            ;;

        *)
            echo "ERROR: Invalid account selector '$ACCOUNT' for $IP"
            exit 1
            ;;
    esac

    echo "Account: $USERNAME"

    # ------------------------------------------------------
    # TEST SSH CONNECTION
    # ------------------------------------------------------

    echo "Testing SSH connection..."

    sshpass -p "$PASSWORD" ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        "$USERNAME@$IP" \
        "echo connected" \
        >/dev/null 2>&1

    SSH_RESULT=$?

    if [[ $SSH_RESULT -ne 0 ]]; then
        echo "Could not connect to $IP"
        FAILED_CONNECTIONS+=("$IP")
        continue
    fi

    echo "SSH connection successful."

    # ------------------------------------------------------
    # DETECT OPERATING SYSTEM
    # ------------------------------------------------------

    echo "Detecting operating system..."

    OS_ID=$(
        sshpass -p "$PASSWORD" ssh \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=10 \
            "$USERNAME@$IP" \
            'source /etc/os-release 2>/dev/null && echo "$ID"' \
            2>/dev/null
    )

    OS_ID=$(echo "$OS_ID" | tr -d '\r' | xargs)

    case "$OS_ID" in

        ubuntu|debian)
            OS_FAMILY="debian"
            ;;

        fedora)
            OS_FAMILY="fedora"
            ;;

        *)
            echo
            echo "ERROR on $IP"
            echo "Unsupported operating system: '$OS_ID'"
            exit 1
            ;;
    esac

    echo "Detected: $OS_ID"

    # ------------------------------------------------------
    # SELECT SCRIPT
    # ------------------------------------------------------

    if [[ "$ACCOUNT" == "user1" && "$OS_FAMILY" == "debian" ]]; then

        SCRIPT_URL="$SCRIPT_USER1_DEBIAN"

    elif [[ "$ACCOUNT" == "user2" && "$OS_FAMILY" == "debian" ]]; then

        SCRIPT_URL="$SCRIPT_USER2_DEBIAN"

    elif [[ "$ACCOUNT" == "user1" && "$OS_FAMILY" == "fedora" ]]; then

        SCRIPT_URL="$SCRIPT_USER1_FEDORA"

    elif [[ "$ACCOUNT" == "user2" && "$OS_FAMILY" == "fedora" ]]; then

        SCRIPT_URL="$SCRIPT_USER2_FEDORA"

    else

        echo "ERROR: Could not select deployment script for $IP"
        exit 1

    fi

    echo "Selected script:"
    echo "$SCRIPT_URL"

    # ------------------------------------------------------
    # RUN REMOTE SCRIPT
    # ------------------------------------------------------

    echo
    echo "Running deployment script on $IP..."

    REMOTE_OUTPUT=$(
        sshpass -p "$PASSWORD" ssh \
            -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=10 \
            "$USERNAME@$IP" \
            "SCRIPT_URL='$SCRIPT_URL' bash -s" <<'REMOTE_COMMAND'
set -e
set -o pipefail

TEMP_SCRIPT="/tmp/prtg-deployment-$$.sh"

cleanup() {
    rm -f "$TEMP_SCRIPT"
}

trap cleanup EXIT

echo "Downloading script..."

if command -v wget >/dev/null 2>&1; then
    wget -q "$SCRIPT_URL" -O "$TEMP_SCRIPT"

elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT"

else
    echo "ERROR: Neither wget nor curl is installed."
    exit 20
fi

if [[ ! -s "$TEMP_SCRIPT" ]]; then
    echo "ERROR: Downloaded script is empty."
    exit 21
fi

chmod +x "$TEMP_SCRIPT"

echo "Starting script..."

sudo bash "$TEMP_SCRIPT"

echo "Deployment completed successfully."
REMOTE_COMMAND
    )

    REMOTE_RESULT=$?

    # ------------------------------------------------------
    # HANDLE REMOTE FAILURE
    # ------------------------------------------------------

    if [[ $REMOTE_RESULT -ne 0 ]]; then

        echo
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "DEPLOYMENT FAILED"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo
        echo "IP address : $IP"
        echo "Username   : $USERNAME"
        echo "OS         : $OS_ID"
        echo "Exit code  : $REMOTE_RESULT"
        echo
        echo "Remote output:"
        echo "------------------------------------------------------"
        echo "$REMOTE_OUTPUT"
        echo "------------------------------------------------------"
        echo
        echo "Stopping deployment."

        exit "$REMOTE_RESULT"
    fi

    echo "$REMOTE_OUTPUT"

    echo
    echo "SUCCESS: $IP"

done < "$INVENTORY"

# ==========================================================
# DELETE PASSWORD VARIABLES
# ==========================================================

unset PASSWORD1
unset PASSWORD2

# ==========================================================
# FINAL REPORT
# ==========================================================

echo
echo "======================================================"
echo "DEPLOYMENT FINISHED"
echo "======================================================"

if [[ ${#FAILED_CONNECTIONS[@]} -eq 0 ]]; then

    echo
    echo "All listed servers were reachable."

else

    echo
    echo "Could not connect to the following servers:"
    echo

    for FAILED_IP in "${FAILED_CONNECTIONS[@]}"; do
        echo "  $FAILED_IP"
    done

fi
