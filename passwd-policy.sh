#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# RHEL 8/9 Password Policy Configuration
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root or with sudo."
    exit 1
fi

echo "============================================================"
echo " Configuring RHEL 8/9 Password Policy"
echo "============================================================"

# ------------------------------------------------------------
# Check operating system
# ------------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

source /etc/os-release

echo "Detected OS: ${PRETTY_NAME:-Unknown}"

if [[ "${ID:-}" != "rhel" &&
      "${ID:-}" != "rocky" &&
      "${ID:-}" != "almalinux" &&
      "${ID:-}" != "centos" ]]; then
    echo "WARNING: This script was designed for RHEL 8/9-compatible systems."
fi


# ------------------------------------------------------------
# Backup configuration
# ------------------------------------------------------------

BACKUP_DIR="/root/password-policy-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

echo
echo "[1/6] Creating backups in:"
echo "      $BACKUP_DIR"

for file in \
    /etc/security/pwquality.conf \
    /etc/security/faillock.conf \
    /etc/security/pwhistory.conf \
    /etc/login.defs
do
    if [[ -f "$file" ]]; then
        cp -a "$file" "$BACKUP_DIR/"
    fi
done

if [[ -d /etc/authselect ]]; then
    cp -a /etc/authselect "$BACKUP_DIR/authselect"
fi


# ------------------------------------------------------------
# Helper function
# ------------------------------------------------------------

set_config_value() {
    local file="$1"
    local key="$2"
    local value="$3"

    touch "$file"

    # Remove active or commented versions of the setting
    sed -ri "/^[[:space:]#]*${key}[[:space:]]*=/d" "$file"

    echo "${key} = ${value}" >> "$file"
}


# ------------------------------------------------------------
# 1. Configure pwquality
# ------------------------------------------------------------

echo
echo "[2/6] Configuring /etc/security/pwquality.conf..."

PWQUALITY="/etc/security/pwquality.conf"

set_config_value "$PWQUALITY" "minlen"   "10"
set_config_value "$PWQUALITY" "minclass" "4"
set_config_value "$PWQUALITY" "dcredit"  "-1"
set_config_value "$PWQUALITY" "ucredit"  "-1"
set_config_value "$PWQUALITY" "lcredit"  "-1"
set_config_value "$PWQUALITY" "ocredit"  "-1"
set_config_value "$PWQUALITY" "retry"    "3"

echo "Password complexity configured."


# ------------------------------------------------------------
# 2. Configure password ageing defaults
# ------------------------------------------------------------

echo
echo "[3/6] Configuring /etc/login.defs..."

LOGIN_DEFS="/etc/login.defs"

set_login_value() {
    local key="$1"
    local value="$2"

    if grep -Eq "^[[:space:]#]*${key}[[:space:]]+" "$LOGIN_DEFS"; then
        sed -ri \
            "s|^[[:space:]#]*${key}[[:space:]]+.*|${key} ${value}|" \
            "$LOGIN_DEFS"
    else
        echo "${key} ${value}" >> "$LOGIN_DEFS"
    fi
}

set_login_value "PASS_MAX_DAYS" "42"
set_login_value "PASS_MIN_DAYS" "1"
set_login_value "PASS_WARN_AGE" "7"

echo "Password ageing defaults configured."


# ------------------------------------------------------------
# 3. Configure faillock
# ------------------------------------------------------------

echo
echo "[4/6] Configuring /etc/security/faillock.conf..."

FAILLOCK="/etc/security/faillock.conf"

set_config_value "$FAILLOCK" "deny"          "6"
set_config_value "$FAILLOCK" "unlock_time"   "1800"
set_config_value "$FAILLOCK" "fail_interval" "900"

echo "Account lockout policy configured."


# ------------------------------------------------------------
# 4. Configure password history
# ------------------------------------------------------------

echo
echo "[5/6] Configuring password history..."

PWHISTORY="/etc/security/pwhistory.conf"

set_config_value "$PWHISTORY" "remember" "10"

if command -v authselect >/dev/null 2>&1; then

    echo "Current authselect configuration:"
    authselect current || true

    # Enable pwhistory if available
    if authselect list-features 2>/dev/null | grep -qx "with-pwhistory"; then

        echo "Enabling authselect with-pwhistory feature..."

        authselect enable-feature with-pwhistory || {
            echo "ERROR: Could not enable with-pwhistory."
            exit 1
        }

    else
        echo "WARNING: authselect does not list with-pwhistory."
        echo "Check PAM password-history configuration manually."
    fi

    echo "Applying authselect configuration..."

    authselect apply-changes

else
    echo "WARNING: authselect was not found."
    echo "PAM password-history configuration may require manual verification."
fi


# ------------------------------------------------------------
# 5. Validate configuration
# ------------------------------------------------------------

echo
echo "[6/6] Verifying configuration..."

echo
echo "---------------- pwquality ----------------"
grep -E \
'^(minlen|minclass|dcredit|ucredit|lcredit|ocredit|retry)[[:space:]]*=' \
"$PWQUALITY" || true

echo
echo "---------------- login.defs ---------------"
grep -E \
'^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE)[[:space:]]+' \
"$LOGIN_DEFS" || true

echo
echo "---------------- faillock -----------------"
grep -E \
'^(deny|unlock_time|fail_interval)[[:space:]]*=' \
"$FAILLOCK" || true

echo
echo "---------------- pwhistory ----------------"
grep -E \
'^remember[[:space:]]*=' \
"$PWHISTORY" || true


echo
echo "============================================================"
echo " Password policy configuration completed."
echo "============================================================"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "IMPORTANT:"
echo "PASS_MAX_DAYS, PASS_MIN_DAYS and PASS_WARN_AGE in"
echo "/etc/login.defs mainly define defaults."
echo
echo "Existing accounts can be updated with:"
echo
echo "  chage -m 1 -M 42 -W 7 USERNAME"
echo
echo "Example:"
echo
echo "  chage -m 1 -M 42 -W 7 sysadmin"
echo
echo "Check an account with:"
echo
echo "  chage -l USERNAME"
echo
echo "Check failed-login state with:"
echo
echo "  faillock --user USERNAME"
echo
echo "Reset failed attempts with:"
echo

rm -- "$0"
echo "  faillock --user USERNAME --reset"
echo
