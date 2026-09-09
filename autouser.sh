#!/usr/bin/env bash

# ============================================================
# CONFIGURATION
# ============================================================

# Username used to SSH into every server.
SSH_USER="your_username"

# One IP address per line.
IP_FILE="ips.txt"

# One password per line.
# Line 1 corresponds to IP line 1, etc.
PASSWORD_FILE="passwords.txt"

# Automation user to create.
AUTOSYS_USER="autosys"

# Hardcoded password for autosys.
AUTOSYS_PASSWORD='CHANGE_THIS_PASSWORD'

# RAW GitHub URL to the script.
# Example:
# https://raw.githubusercontent.com/user/repository/main/setup.sh
GITHUB_SCRIPT_URL="https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/script.sh"

# Location where the script will temporarily be downloaded.
# Your GitHub script is expected to delete itself after execution.
REMOTE_SCRIPT="/tmp/autosys_setup.sh"


# ============================================================
# LOCAL REQUIREMENTS
# ============================================================

if ! command -v ssh >/dev/null 2>&1; then
    echo "ERROR: ssh is not installed."
    exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass is not installed."
    echo
    echo "Ubuntu/Debian:"
    echo "  sudo apt install sshpass"
    echo
    echo "Fedora:"
    echo "  sudo dnf install sshpass"
    exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
    echo "ERROR: base64 is not installed."
    exit 1
fi


# ============================================================
# CHECK INPUT FILES
# ============================================================

if [[ ! -f "$IP_FILE" ]]; then
    echo "ERROR: IP file not found: $IP_FILE"
    exit 1
fi

if [[ ! -f "$PASSWORD_FILE" ]]; then
    echo "ERROR: Password file not found: $PASSWORD_FILE"
    exit 1
fi


# ============================================================
# LOAD IP ADDRESSES AND PASSWORDS
# ============================================================

mapfile -t IPS < "$IP_FILE"
mapfile -t PASSWORDS < "$PASSWORD_FILE"

if [[ "${#IPS[@]}" -ne "${#PASSWORDS[@]}" ]]; then
    echo "ERROR: Number of IP addresses and passwords does not match."
    echo
    echo "IP addresses: ${#IPS[@]}"
    echo "Passwords:    ${#PASSWORDS[@]}"
    exit 1
fi

if [[ "${#IPS[@]}" -eq 0 ]]; then
    echo "ERROR: No IP addresses were found."
    exit 1
fi


# ============================================================
# RESULT ARRAYS
# ============================================================

SUCCESSFUL=()
FAILED=()
FAILED_SSH=()
FAILED_REMOTE=()


# ============================================================
# HELPER
# ============================================================

encode_base64() {
    printf '%s' "$1" | base64 | tr -d '\n'
}


# ============================================================
# START
# ============================================================

echo
echo "============================================================"
echo "               AUTOSYS DEPLOYMENT START"
echo "============================================================"
echo
echo "Servers to process: ${#IPS[@]}"
echo


# ============================================================
# LOOP THROUGH SERVERS
# ============================================================

for i in "${!IPS[@]}"; do

    # Remove Windows CR character if files were created on Windows.
    IP="${IPS[$i]%$'\r'}"
    LOGIN_PASSWORD="${PASSWORDS[$i]%$'\r'}"

    SERVER_NUMBER=$((i + 1))

    echo
    echo "============================================================"
    echo " [$SERVER_NUMBER/${#IPS[@]}] SERVER: $IP"
    echo "============================================================"

    # Do not allow blank entries because they could misalign credentials.
    if [[ -z "$IP" ]]; then
        echo "ERROR: Empty IP address on line $SERVER_NUMBER."
        FAILED+=("line-$SERVER_NUMBER")
        FAILED_REMOTE+=("line-$SERVER_NUMBER")
        continue
    fi

    if [[ -z "$LOGIN_PASSWORD" ]]; then
        echo "ERROR: Empty password for $IP."
        FAILED+=("$IP")
        FAILED_SSH+=("$IP")
        continue
    fi


    # ========================================================
    # PREPARE VARIABLES SAFELY FOR REMOTE SYSTEM
    # ========================================================

    LOGIN_PASSWORD_B64=$(encode_base64 "$LOGIN_PASSWORD")
    AUTOSYS_PASSWORD_B64=$(encode_base64 "$AUTOSYS_PASSWORD")
    GITHUB_SCRIPT_URL_B64=$(encode_base64 "$GITHUB_SCRIPT_URL")

    export SSHPASS="$LOGIN_PASSWORD"


    # ========================================================
    # CONNECT TO SERVER
    # ========================================================

    sshpass -e ssh \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=2 \
        -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$IP" \
        "bash -s -- \
        '$LOGIN_PASSWORD_B64' \
        '$AUTOSYS_PASSWORD_B64' \
        '$GITHUB_SCRIPT_URL_B64' \
        '$AUTOSYS_USER' \
        '$REMOTE_SCRIPT'" <<'REMOTE_EOF'

# ============================================================
# REMOTE SCRIPT
# ============================================================

set -Eeuo pipefail

LOGIN_PASSWORD_B64="$1"
AUTOSYS_PASSWORD_B64="$2"
GITHUB_SCRIPT_URL_B64="$3"
AUTOSYS_USER="$4"
REMOTE_SCRIPT="$5"

CURRENT_STAGE="initialization"


# ============================================================
# GENERAL ERROR HANDLER
# ============================================================

error_handler() {

    EXIT_CODE=$?

    echo
    echo "------------------------------------------------------------"
    echo "ERROR: Deployment failed."
    echo "Stage: $CURRENT_STAGE"
    echo "Exit code: $EXIT_CODE"
    echo "------------------------------------------------------------"

    exit "$EXIT_CODE"
}

trap error_handler ERR


# ============================================================
# DECODE VARIABLES
# ============================================================

CURRENT_STAGE="decoding deployment parameters"

LOGIN_PASSWORD=$(printf '%s' "$LOGIN_PASSWORD_B64" | base64 -d)
AUTOSYS_PASSWORD=$(printf '%s' "$AUTOSYS_PASSWORD_B64" | base64 -d)
GITHUB_SCRIPT_URL=$(printf '%s' "$GITHUB_SCRIPT_URL_B64" | base64 -d)

unset LOGIN_PASSWORD_B64
unset AUTOSYS_PASSWORD_B64
unset GITHUB_SCRIPT_URL_B64


echo
echo "[1/7] SSH connection successful."


# ============================================================
# VERIFY SUDO
# ============================================================

CURRENT_STAGE="sudo authentication"

echo
echo "[2/7] Verifying sudo access..."

if ! printf '%s\n' "$LOGIN_PASSWORD" | sudo -S -p '' -v; then

    echo
    echo "ERROR: Sudo authentication failed."
    echo "The SSH password may not be the sudo password,"
    echo "or the SSH user may not have sudo permission."

    exit 20
fi

# Password is no longer needed by our shell.
unset LOGIN_PASSWORD

echo "Sudo authentication successful."


# ============================================================
# DETECT OPERATING SYSTEM
# ============================================================

CURRENT_STAGE="operating system detection"

echo
echo "[3/7] Detecting operating system..."

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: /etc/os-release does not exist."
    exit 30
fi

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in

    ubuntu)

        OS_TYPE="ubuntu"
        SUDO_GROUP="sudo"

        ;;

    fedora)

        OS_TYPE="fedora"
        SUDO_GROUP="wheel"

        ;;

    *)

        echo
        echo "ERROR: Unsupported operating system."
        echo "Detected ID: ${ID:-unknown}"
        echo "Detected system: ${PRETTY_NAME:-unknown}"

        exit 31

        ;;

esac

echo "Operating system: $PRETTY_NAME"
echo "Type: $OS_TYPE"
echo "Sudo group: $SUDO_GROUP"


# ============================================================
# VERIFY REQUIRED REMOTE COMMANDS
# ============================================================

CURRENT_STAGE="checking required commands"

if ! command -v wget >/dev/null 2>&1; then
    echo "ERROR: wget is not installed on this server."
    exit 32
fi

if ! command -v useradd >/dev/null 2>&1; then
    echo "ERROR: useradd is not available."
    exit 33
fi

if ! command -v chpasswd >/dev/null 2>&1; then
    echo "ERROR: chpasswd is not available."
    exit 34
fi

if ! command -v chage >/dev/null 2>&1; then
    echo "ERROR: chage is not available."
    exit 35
fi


# ============================================================
# CREATE AUTOSYS USER
# ============================================================

CURRENT_STAGE="autosys user creation"

echo
echo "[4/7] Configuring user: $AUTOSYS_USER"

if id "$AUTOSYS_USER" >/dev/null 2>&1; then

    echo "User $AUTOSYS_USER already exists."
    echo "The existing account will be updated."

else

    echo "Creating user $AUTOSYS_USER..."

    sudo useradd \
        --create-home \
        --shell /bin/bash \
        "$AUTOSYS_USER"

    echo "User created successfully."

fi


# ============================================================
# SET AUTOSYS PASSWORD
# ============================================================

CURRENT_STAGE="autosys password configuration"

echo
echo "Setting password for $AUTOSYS_USER..."

printf '%s:%s\n' \
    "$AUTOSYS_USER" \
    "$AUTOSYS_PASSWORD" \
    | sudo chpasswd

echo "Password configured successfully."


# ============================================================
# PASSWORD EXPIRATION
# ============================================================

CURRENT_STAGE="autosys password expiration configuration"

echo
echo "[5/7] Setting password lifetime to 90 days..."

sudo chage \
    -M 90 \
    -W 7 \
    "$AUTOSYS_USER"

echo "Password lifetime configured."
echo "Password will expire after 90 days."


# ============================================================
# ADD SUDO PERMISSIONS
# ============================================================

CURRENT_STAGE="autosys sudo permission configuration"

echo
echo "Adding $AUTOSYS_USER to $SUDO_GROUP..."

if ! getent group "$SUDO_GROUP" >/dev/null 2>&1; then

    echo
    echo "ERROR: Expected sudo group '$SUDO_GROUP' does not exist."

    exit 36
fi

sudo usermod \
    -aG "$SUDO_GROUP" \
    "$AUTOSYS_USER"

echo "Sudo group configured successfully."


# ============================================================
# REMOVE SENSITIVE VARIABLE
# ============================================================

unset AUTOSYS_PASSWORD


# ============================================================
# REMOVE POSSIBLE OLD SCRIPT
# ============================================================

CURRENT_STAGE="removing previous downloaded script"

echo
echo "Checking for an old copy of the deployment script..."

if [[ -e "$REMOTE_SCRIPT" ]]; then

    echo "Old copy found at:"
    echo "  $REMOTE_SCRIPT"

    echo "Removing old copy..."

    sudo rm -f "$REMOTE_SCRIPT"

fi


# ============================================================
# DOWNLOAD GITHUB SCRIPT
# ============================================================

CURRENT_STAGE="GitHub script download"

echo
echo "[6/7] Downloading GitHub script..."
echo "Destination: $REMOTE_SCRIPT"

if ! sudo wget \
    --output-document="$REMOTE_SCRIPT" \
    "$GITHUB_SCRIPT_URL"; then

    echo
    echo "ERROR: wget failed."
    echo "Could not download the GitHub script."

    exit 40
fi


# ============================================================
# VERIFY DOWNLOAD
# ============================================================

CURRENT_STAGE="GitHub script verification"

if [[ ! -f "$REMOTE_SCRIPT" ]]; then

    echo
    echo "ERROR: Script was not created after wget."

    exit 41
fi

if [[ ! -s "$REMOTE_SCRIPT" ]]; then

    echo
    echo "ERROR: Downloaded GitHub script is empty."

    exit 42
fi

echo
echo "GitHub script downloaded successfully."


# ============================================================
# MAKE SCRIPT EXECUTABLE
# ============================================================

CURRENT_STAGE="GitHub script chmod"

echo "Making GitHub script executable..."

sudo chmod +x "$REMOTE_SCRIPT"


# ============================================================
# REFRESH SUDO SESSION
# ============================================================

CURRENT_STAGE="refreshing sudo credentials"

# All previous sudo commands should have kept the timestamp active,
# but verify that sudo is still cached before running the main script.

if ! sudo -n true; then

    echo
    echo "ERROR: Sudo authentication cache expired unexpectedly."

    exit 43
fi


# ============================================================
# RUN GITHUB SCRIPT
# ============================================================

CURRENT_STAGE="GitHub script execution"

echo
echo "[7/7] Executing GitHub script..."
echo
echo "------------------------------------------------------------"
echo "BEGIN GITHUB SCRIPT OUTPUT"
echo "------------------------------------------------------------"
echo

set +e

sudo "$REMOTE_SCRIPT"

SCRIPT_EXIT_CODE=$?

set -e

echo
echo "------------------------------------------------------------"
echo "END GITHUB SCRIPT OUTPUT"
echo "------------------------------------------------------------"


# ============================================================
# CHECK GITHUB SCRIPT RESULT
# ============================================================

if [[ "$SCRIPT_EXIT_CODE" -ne 0 ]]; then

    echo
    echo "ERROR: GitHub script failed."
    echo "GitHub script exit code: $SCRIPT_EXIT_CODE"

    exit "$SCRIPT_EXIT_CODE"
fi

echo
echo "GitHub script completed successfully."

# NOTE:
# We intentionally DO NOT remove $REMOTE_SCRIPT here.
# The downloaded script handles its own deletion.


# ============================================================
# FINAL VERIFICATION
# ============================================================

CURRENT_STAGE="final autosys verification"

echo
echo "Verifying $AUTOSYS_USER..."

sudo id "$AUTOSYS_USER"

echo
echo "Password aging information:"
echo

sudo chage -l "$AUTOSYS_USER"

echo
echo "Group membership:"
sudo groups "$AUTOSYS_USER"


# ============================================================
# FINISHED
# ============================================================

echo
echo "============================================================"
echo " SERVER CONFIGURATION COMPLETED SUCCESSFULLY"
echo "============================================================"

exit 0

REMOTE_EOF

    SSH_STATUS=$?

    unset SSHPASS
    unset LOGIN_PASSWORD
    unset LOGIN_PASSWORD_B64
    unset AUTOSYS_PASSWORD_B64
    unset GITHUB_SCRIPT_URL_B64


    # ========================================================
    # HANDLE RESULT
    # ========================================================

    if [[ "$SSH_STATUS" -eq 0 ]]; then

        echo
        echo "============================================================"
        echo " SUCCESS: $IP"
        echo "============================================================"

        SUCCESSFUL+=("$IP")

    elif [[ "$SSH_STATUS" -eq 255 ]]; then

        echo
        echo "============================================================"
        echo " SSH FAILURE: $IP"
        echo "============================================================"
        echo
        echo "Possible causes:"
        echo "  - Wrong SSH password"
        echo "  - SSH service unavailable"
        echo "  - Server unreachable"
        echo "  - Port 22 blocked"
        echo "  - SSH host key changed"

        FAILED+=("$IP")
        FAILED_SSH+=("$IP")

    else

        echo
        echo "============================================================"
        echo " REMOTE DEPLOYMENT FAILED: $IP"
        echo " Exit code: $SSH_STATUS"
        echo "============================================================"

        FAILED+=("$IP")
        FAILED_REMOTE+=("$IP")

    fi

done


# ============================================================
# FINAL REPORT
# ============================================================

echo
echo
echo "################################################################"
echo "#                        FINAL REPORT                          #"
echo "################################################################"

echo
echo "Total servers:"
echo "  ${#IPS[@]}"

echo
echo "Successful:"
echo "  ${#SUCCESSFUL[@]}"

if [[ "${#SUCCESSFUL[@]}" -gt 0 ]]; then

    for IP in "${SUCCESSFUL[@]}"; do
        echo "    + $IP"
    done

fi


echo
echo "Failed:"
echo "  ${#FAILED[@]}"

if [[ "${#FAILED[@]}" -gt 0 ]]; then

    for IP in "${FAILED[@]}"; do
        echo "    - $IP"
    done

fi


echo
echo "SSH / connection failures:"
echo "  ${#FAILED_SSH[@]}"

if [[ "${#FAILED_SSH[@]}" -gt 0 ]]; then

    for IP in "${FAILED_SSH[@]}"; do
        echo "    - $IP"
    done

fi


echo
echo "Remote configuration/script failures:"
echo "  ${#FAILED_REMOTE[@]}"

if [[ "${#FAILED_REMOTE[@]}" -gt 0 ]]; then

    for IP in "${FAILED_REMOTE[@]}"; do
        echo "    - $IP"
    done

fi


echo
echo "################################################################"


# ============================================================
# EXIT STATUS
# ============================================================

if [[ "${#FAILED[@]}" -gt 0 ]]; then
    exit 1
fi

exit 0
