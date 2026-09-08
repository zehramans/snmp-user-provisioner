# ============================================================
# CHECK SNMP CONFIGURATION
# ============================================================

SNMP_CONF="/etc/snmp/snmpd.conf"

if [[ -f "$SNMP_CONF" ]]; then
    echo "[OK] SNMP configuration found: $SNMP_CONF"
else
    echo "[!] SNMP configuration not found: $SNMP_CONF"
    echo
    echo "Paste the contents of snmpd.conf below."
    echo "When finished, type EOF on a new line and press Enter:"
    echo "------------------------------------------------------------"

    TMP_SNMP_CONF=$(mktemp)

    while IFS= read -r line; do
        [[ "$line" == "EOF" ]] && break
        printf '%s\n' "$line" >> "$TMP_SNMP_CONF"
    done

    if [[ ! -s "$TMP_SNMP_CONF" ]]; then
        echo "ERROR: No configuration was provided."
        rm -f "$TMP_SNMP_CONF"
        exit 1
    fi

    # Make sure directory exists
    sudo mkdir -p "$(dirname "$SNMP_CONF")"

    # Install with root ownership and restrictive permissions
    sudo install -o root -g root -m 600 "$TMP_SNMP_CONF" "$SNMP_CONF"

    rm -f "$TMP_SNMP_CONF"

    echo
    echo "[OK] Created $SNMP_CONF"
fi

# The rest of your script continues here...
echo "Continuing..."
