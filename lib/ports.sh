#!/bin/bash
# multifon v2 — lib/ports.sh
# Port registry + allocation. Format is unchanged from v1 so existing
# instances keep working:
#   psiphon/.allocated_ports  — one line per instance: "<name> <http_port> <socks_port>"
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_PORTS_LOADED:-}" ]] && return 0
_MULTIFON_PORTS_LOADED=1

# Persistent port registry (to avoid collisions across runs)
PORT_REG_FILE="$PSIPHON_BASE_DIR/psiphon/.allocated_ports"

port_registry_init() {
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
    [ -f "$PORT_REG_FILE" ] || : > "$PORT_REG_FILE"
}

port_registry_used_ports() {
    # prints list of ports (one per line) from registry
    awk '{print $2"\n"$3}' "$PORT_REG_FILE" 2>/dev/null | awk 'NF'
}

port_registry_set_entry() {
    # usage: port_registry_set_entry <name> <http_port> <socks_port>
    local name="$1" http="$2" socks="$3"
    (
        # lock registry file during update
        flock -w 3 9 || { echo "${YELLOW}Port registry busy, skipping write for $name${RESET}"; exit 0; }
        tmp=$(mktemp)
        grep -v "^${name} " "$PORT_REG_FILE" 2>/dev/null > "$tmp" || true
        printf '%s %s %s\n' "$name" "$http" "$socks" >> "$tmp"
        mv "$tmp" "$PORT_REG_FILE"
    ) 9>>"$PORT_REG_FILE"
}

port_registry_del_entry() {
    # usage: port_registry_del_entry <name>
    local name="$1"
    [ -f "$PORT_REG_FILE" ] || return 0
    (
        flock -w 3 9 || exit 0
        tmp=$(mktemp)
        grep -v "^${name} " "$PORT_REG_FILE" 2>/dev/null > "$tmp" || true
        mv "$tmp" "$PORT_REG_FILE"
    ) 9>>"$PORT_REG_FILE"
}

# usage: port_registry_get <name>  -> prints "<http> <socks>" or nothing
port_registry_get() {
    local name="$1"
    [ -f "$PORT_REG_FILE" ] || return 1
    awk -v n="$name" '$1 == n { print $2, $3; exit }' "$PORT_REG_FILE"
}

# Helper: check if a port is in use (ss/netstat fallback)
port_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":$1 "
    else
        netstat -tuln 2>/dev/null | grep -q ":$1 "
    fi
}

# Helper: next free port within a range (avoids already-picked ports too)
next_free_port_in_range() {
    local start="$1" end="$2" p
    for ((p=start; p<=end; p++)); do
        if ! port_in_use "$p" && ! [[ " ${used_ports[*]} " == *" $p "* ]]; then
            echo "$p"; return 0
        fi
    done
    return 1
}

# Helper: next free port from a starting point upward (fallback)
next_free_port_any() {
    local p="$1"
    while true; do
        if ! port_in_use "$p" && ! [[ " ${used_ports[*]} " == *" $p "* ]]; then
            echo "$p"; return 0
        fi
        ((p++))
    done
}

# Helper: collect ports from existing configs so we never reuse them
collect_existing_ports() {
    local cfg hp sp
    while IFS= read -r cfg; do
        if command -v jq >/dev/null 2>&1; then
            hp=$(jq -r '.LocalHttpProxyPort // empty' "$cfg")
            sp=$(jq -r '.LocalSocksProxyPort // empty' "$cfg")
        else
            hp=$(grep -oE '"LocalHttpProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
            sp=$(grep -oE '"LocalSocksProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
        fi
        [[ -n "$hp" ]] && used_ports+=("$hp")
        [[ -n "$sp" ]] && used_ports+=("$sp")
    done < <( find "$HOME/psiphon" -maxdepth 2 -type f -name 'config.json' 2>/dev/null \
              | grep -E '/psiphon-[^/]+/config\.json$' | sort -u )
}

# Read the HTTP/SOCKS ports of one instance folder from its config.json.
# usage: instance_ports <dir>  -> prints "<http> <socks>" ("-" for missing)
instance_ports() {
    local cfg="$1/config.json" hp="-" sp="-"
    if [ -f "$cfg" ]; then
        if command -v jq >/dev/null 2>&1; then
            hp=$(jq -r '.LocalHttpProxyPort // "-"' "$cfg")
            sp=$(jq -r '.LocalSocksProxyPort // "-"' "$cfg")
        else
            hp=$(grep -oE '"LocalHttpProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
            sp=$(grep -oE '"LocalSocksProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
            hp="${hp:--}"; sp="${sp:--}"
        fi
    fi
    echo "$hp $sp"
}
