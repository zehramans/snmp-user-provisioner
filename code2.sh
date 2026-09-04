#!/usr/bin/env bash

set -u
set -o pipefail

# ============================================================
# CONFIGURATION
# ============================================================

INVENTORY="servers.tsv"

# The two usernames used in your environment
USER1="admin1"
USER2="admin2"

# ------------------------------------------------------------
# GitHub RAW links
#
# IMPORTANT:
# These need to be RAW GitHub URLs, for example:
#
# https://raw.githubusercontent.com/user/repo/main/script.sh
# ------------------------------------------------------------

USER1_DEBIAN_SCRIPT="https://raw.githubusercontent.com/YOU/REPO/main/user1_debian.sh"
USER1_FEDORA_SCRIPT="https://raw.githubusercontent.com/YOU/REPO/main/user1_fedora.sh"

USER2_DEBIAN_SCRIPT="https://raw.githubusercontent.com/YOU/REPO/main/user2_debian.sh"
USER2_FEDORA_SCRIPT="https://raw.githubusercontent.com/YOU/REPO/main/user2_fedora.sh"

SSH_TIMEOUT=10

# ============================================================
# CHECKS
# ============================================================

if [[ ! -f "$INVENTORY" ]]; then
    echo "ERROR: Inventory file not found: $INVENTORY"
    exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass is not installed."
    echo "Install it first."
    exit 1
fi

# Protect the file containing passwords.
chmod 600 "$INVENTORY"

FAILED_IPS=()
SUCCESS_REPORT=()

# ============================================================
# SSH HELPER
# ============================================================

run_ssh() {
    local ip="$1"
    local username="$2"
    local password="$3"
    shift 3

    SSHPASS="$password" sshpass -e ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        "$username@$ip" \
        "$@"
}

# ============================================================
# MAIN LOOP
# ============================================================

while IFS=$'\t' read -r ip username current_password new_password || [[ -n "$ip" ]]; do

    # Ignore blank lines
    [[ -z "$ip" ]] && continue

    # Ignore comments
    [[ "$ip" =~ ^[[:space:]]*# ]] && continue

    echo
    echo "============================================================"
    echo "Processing: $ip"
    echo "Username:   $username"
    echo "============================================================"

    # --------------------------------------------------------
    # Validate username
    # --------------------------------------------------------

    if [[ "$username" != "$USER1" && "$username" != "$USER2" ]]; then
        echo "ERROR: Unknown username '$username' for $ip"
        exit 1
    fi

    # --------------------------------------------------------
    # Test SSH
    #
    # SSH failures are collected. We continue to the next IP.
    # --------------------------------------------------------

    echo "[1/5] Testing SSH..."

    ssh_output=$(
        run_ssh \
            "$ip" \
            "$username" \
            "$current_password" \
            "echo SSH_OK" \
            2>&1
    )

    ssh_status=$?

    if [[ $ssh_status -ne 0 ]]; then
        echo "SSH FAILED: $ip"
        echo "$ssh_output"

        FAILED_IPS+=("$ip")
        continue
    fi

    echo "SSH successful."

    # --------------------------------------------------------
    # Detect OS
    # --------------------------------------------------------

    echo "[2/5] Detecting operating system..."

    os_info=$(
        run_ssh \
            "$ip" \
            "$username" \
            "$current_password" \
            'source /etc/os-release 2>/dev/null && printf "%s|%s\n" "$ID" "${ID_LIKE:-}"' \
            2>&1
    )

    os_status=$?

    if [[ $os_status -ne 0 ]]; then
        echo
        echo "FATAL ERROR on $ip"
        echo "Could not detect operating system."
        echo
        echo "$os_info"
        exit 1
    fi

    os_id="${os_info%%|*}"
    os_like="${os_info#*|}"

    echo "Detected OS: $os_id"
    echo "OS family:   $os_like"

    # --------------------------------------------------------
    # Determine OS family
    # --------------------------------------------------------

    OS_FAMILY=""

    case "$os_id" in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        fedora)
            OS_FAMILY="fedora"
            ;;
        *)
            if [[ "$os_like" == *debian* ]]; then
                OS_FAMILY="debian"
            elif [[ "$os_like" == *fedora* || "$os_like" == *rhel* ]]; then
                OS_FAMILY="fedora"
            else
                echo
                echo "FATAL ERROR on $ip"
                echo "Unsupported operating system: $os_id"
                exit 1
            fi
            ;;
    esac

    echo "Selected family: $OS_FAMILY"

    # --------------------------------------------------------
    # Select GitHub script
    # --------------------------------------------------------

    echo "[3/5] Selecting deployment script..."

    SCRIPT_URL=""

    if [[ "$username" == "$USER1" && "$OS_FAMILY" == "debian" ]]; then
        SCRIPT_URL="$USER1_DEBIAN_SCRIPT"

    elif [[ "$username" == "$USER1" && "$OS_FAMILY" == "fedora" ]]; then
        SCRIPT_URL="$USER1_FEDORA_SCRIPT"

    elif [[ "$username" == "$USER2" && "$OS_FAMILY" == "debian" ]]; then
        SCRIPT_URL="$USER2_DEBIAN_SCRIPT"

    elif [[ "$username" == "$USER2" && "$OS_FAMILY" == "fedora" ]]; then
        SCRIPT_URL="$USER2_FEDORA_SCRIPT"

    else
        echo "FATAL ERROR on $ip"
        echo "Could not determine which script should run."
        exit 1
    fi

    echo "Selected script:"
    echo "$SCRIPT_URL"

    # --------------------------------------------------------
    # Download and execute remote script
    #
    # The NEW password is supplied twice on stdin.
    #
    # This works if your GitHub script uses normal stdin reads.
    #
    # Example:
    #
    # read -s PASSWORD
    # read -s PASSWORD_CONFIRM
    #
    # If the script directly invokes interactive `passwd`,
    # see explanation below.
    # --------------------------------------------------------

    echo "[4/5] Downloading and executing script..."

    # Base64 avoids shell quoting problems with most passwords.
    new_password_b64=$(
        printf '%s' "$new_password" | base64 | tr -d '\n'
    )

    remote_command=$(cat <<EOF
set -euo pipefail

TEMP_SCRIPT=\$(mktemp /tmp/server_setup.XXXXXX.sh)

cleanup() {
    rm -f "\$TEMP_SCRIPT"
}

trap cleanup EXIT

if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "\$TEMP_SCRIPT" "$SCRIPT_URL"
elif command -v curl >/dev/null 2>&1; then
    curl -fL -o "\$TEMP_SCRIPT" "$SCRIPT_URL"
else
    echo "ERROR: Neither wget nor curl exists on this server." >&2
    exit 20
fi

chmod 700 "\$TEMP_SCRIPT"

NEW_PASSWORD=\$(printf '%s' "$new_password_b64" | base64 -d)

printf '%s\n%s\n' "\$NEW_PASSWORD" "\$NEW_PASSWORD" | bash "\$TEMP_SCRIPT"

unset NEW_PASSWORD
EOF
)

    script_output=$(
        run_ssh \
            "$ip" \
            "$username" \
            "$current_password" \
            "$remote_command" \
            2>&1
    )

    script_status=$?

    if [[ $script_status -ne 0 ]]; then
        echo
        echo "============================================================"
        echo "FATAL REMOTE SCRIPT ERROR"
        echo "============================================================"
        echo "IP:       $ip"
        echo "Username: $username"
        echo "Exit code: $script_status"
        echo
        echo "REMOTE OUTPUT:"
        echo "------------------------------------------------------------"
        echo "$script_output"
        echo "------------------------------------------------------------"
        echo
        echo "Execution stopped immediately."
        exit 1
    fi

    echo "$script_output"
    echo
    echo "Remote script completed successfully."

    # --------------------------------------------------------
    # Record result
    # --------------------------------------------------------

    echo "[5/5] Recording result..."

    SUCCESS_REPORT+=("$ip"$'\t'"$username"$'\t'"$new_password")

    echo "DONE: $ip"

done < "$INVENTORY"

# ============================================================
# FINAL REPORT
# ============================================================

echo
echo
echo "================================================================="
echo "DEPLOYMENT COMPLETE"
echo "================================================================="

echo
echo "SUCCESSFUL SERVERS"
echo "-----------------------------------------------------------------"

if [[ ${#SUCCESS_REPORT[@]} -eq 0 ]]; then
    echo "None"
else
    printf "%-18s %-20s %s\n" "IP ADDRESS" "USERNAME" "NEW PASSWORD"
    printf "%-18s %-20s %s\n" "----------" "--------" "------------"

    for entry in "${SUCCESS_REPORT[@]}"; do
        IFS=$'\t' read -r report_ip report_user report_password <<< "$entry"

        printf "%-18s %-20s %s\n" \
            "$report_ip" \
            "$report_user" \
            "$report_password"
    done
fi

echo
echo "FAILED SSH CONNECTIONS"
echo "-----------------------------------------------------------------"

if [[ ${#FAILED_IPS[@]} -eq 0 ]]; then
    echo "None"
else
    for failed_ip in "${FAILED_IPS[@]}"; do
        echo "$failed_ip"
    done
fi

echo
echo "================================================================="
