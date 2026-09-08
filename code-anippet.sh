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
