#!/bin/bash
# multifon v2.1 — lib/firewall.sh
# iptables port open/block controls (bug #7 — new in v2).
# Rules are tagged with a "multifon:<name>" comment so they can be listed
# and removed again. nft is a best-effort fallback; if neither iptables
# nor nft exists, the menu says so instead of failing silently.
# Nothing here is persisted across reboots by itself — the rules live in
# the running firewall only, exactly like a manual iptables command.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_FIREWALL_LOADED:-}" ]] && return 0
_MULTIFON_FIREWALL_LOADED=1

# Detect the available backend: "iptables", "nft", or "".
firewall_backend() {
    if command -v iptables >/dev/null 2>&1; then
        echo "iptables"
    elif command -v nft >/dev/null 2>&1; then
        echo "nft"
    else
        echo ""
    fi
}

# iptables helpers (rules carry a comment so they stay identifiable).
_fw_iptables_has() {
    # _fw_iptables_has <chain> <rule...>
    local chain="$1"; shift
    sudo iptables -C "$chain" "$@" >/dev/null 2>&1
}

_fw_iptables_add() {
    # _fw_iptables_add <chain> <rule...>
    local chain="$1"; shift
    _fw_iptables_has "$chain" "$@" && return 0
    sudo iptables -A "$chain" "$@"
}

_fw_iptables_del() {
    local chain="$1"; shift
    sudo iptables -D "$chain" "$@" >/dev/null 2>&1 || true
}

# Open a TCP port in INPUT for one instance.
# Usage: firewall_open_port <port> <name> [proto]  (proto defaults to tcp)
firewall_open_port() {
    local port="$1" name="$2" proto="${3:-tcp}"
    [[ "$port" =~ ^[0-9]+$ ]] || { echo -e "${RED}Bad port: $port${RESET}"; return 1; }
    case "$(firewall_backend)" in
        iptables)
            _fw_iptables_add INPUT -p "$proto" --dport "$port" -m comment --comment "multifon:$name" -j ACCEPT
            echo -e "${GREEN}Port $port/$proto opened (multifon:$name).${RESET}"
            ;;
        nft)
            sudo nft add rule inet filter input "$proto" dport "$port" accept 2>/dev/null
            echo -e "${GREEN}Port $port/$proto opened via nft (no comment tracking on nft).${RESET}"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

# Block a TCP port in INPUT (inserted first so it wins over ACCEPT rules).
# Usage: firewall_block_port <port> <name> [proto]
firewall_block_port() {
    local port="$1" name="$2" proto="${3:-tcp}"
    [[ "$port" =~ ^[0-9]+$ ]] || { echo -e "${RED}Bad port: $port${RESET}"; return 1; }
    case "$(firewall_backend)" in
        iptables)
            sudo iptables -I INPUT 1 -p "$proto" --dport "$port" -m comment --comment "multifon:$name" -j DROP
            echo -e "${GREEN}Port $port/$proto blocked (multifon:$name).${RESET}"
            ;;
        nft)
            sudo nft insert rule inet filter input position 0 "$proto" dport "$port" drop 2>/dev/null
            echo -e "${GREEN}Port $port/$proto blocked via nft.${RESET}"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

# Remove every multifon rule that belongs to one instance name.
# Usage: firewall_close_instance_ports <name>
firewall_close_instance_ports() {
    local name="$1"
    case "$(firewall_backend)" in
        iptables)
            local line rule
            while IFS= read -r line; do
                rule="${line#-A INPUT }"
                # only touch rules tagged with our comment for this name
                [[ "$line" == *"multifon:$name"* ]] || continue
                # shellcheck disable=SC2086
                sudo iptables -D INPUT $rule >/dev/null 2>&1 || true
            done < <(sudo iptables -S INPUT 2>/dev/null | grep -F "multifon:$name" || true)
            ;;
        nft)
            echo -e "${YELLOW}nft rules are not tagged per instance — remove them manually (nft list ruleset).${RESET}"
            ;;
        *) ;;
    esac
}

# List all multifon firewall rules.
firewall_list() {
    case "$(firewall_backend)" in
        iptables)
            echo -e "${YELLOW}multifon iptables rules (INPUT):${RESET}"
            sudo iptables -S INPUT 2>/dev/null | grep -F "multifon:" || echo -e " (none)"
            echo -e "${YELLOW}multifon iptables rules (OUTPUT):${RESET}"
            sudo iptables -S OUTPUT 2>/dev/null | grep -F "multifon:" || echo -e " (none)"
            ;;
        nft)
            echo -e "${YELLOW}nft ruleset (grep multifon ports manually):${RESET}"
            sudo nft list ruleset 2>/dev/null | grep -E 'dport|drop|accept|reject' || echo -e " (none)"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

# --- Scoped egress blocks: DNS (port 53) + STUN (3478/5349/19302) --------
# v2.1 — this REPLACES the v2.0 server-wide OUTPUT block on port 53.
# Why v2.0 was wrong: Xray's own DNS uses plain 1.1.1.1 / 9.9.9.9 on
# port 53, so a server-wide block kills DNS for every 3x-ui config,
# plus apt and dig on the server. The user caught this live (menu 8
# warned about it, and he cancelled with Ctrl+C).
#
# Mechanism chosen: iptables owner match (-m owner --uid-owner).
# Why this one: the Psiphon instances are the only processes that must
# never speak plain DNS or STUN. They run inside firejail sandboxes,
# and firejail can run as an unprivileged user (the binary is setuid),
# so the instances are launched as a dedicated system user `multifon`
# and the OUTPUT rules match only that uid. Xray runs as root, apt runs
# as root, dig runs as root — none of them match, so they keep working.
# Why not the alternatives: a server-wide OUTPUT rule breaks Xray (see
# above); firejail --netfilter needs a private network namespace, which
# the current --noprofile --private setup does not create; a cgroup
# match needs systemd-run per instance, which the oneshot launcher
# does not use.
#
# One deliberate exception — the bootstrap allow-list: the Psiphon core
# itself needs DNS to fetch its remote server list at startup, so the
# sandbox uid may still query 1.1.1.1, 8.8.8.8 and 9.9.9.9 on port 53.
# Everything ELSE on port 53 for that uid is REJECTed. That stops leaks
# to arbitrary / ISP resolvers (the country-mismatch case). The full
# "no direct DNS at all" variant — a local DoH forwarder + firejail
# --dns pointing at it — is Phase 4; the forwarder does not exist yet.
# STUN needs no exception: the core never uses STUN. The STUN rule
# therefore REJECTs all three ports for the sandbox uid, no allow-list.
#
# The rules use REJECT (fail fast) instead of DROP, so a blocked query
# fails immediately instead of hanging until timeout.
# Enabling the scoped block the first time creates the `multifon` user,
# chowns the instance folders to it, and regenerates + restarts the
# launchers so new processes run as that uid. "Disable" removes exactly
# the tagged rules that "enable" added — nothing else.

SANDBOX_USER="multifon"
SANDBOX_UID_FILE="$PSIPHON_BASE_DIR/psiphon/.sandbox-uid"
STUN_PORTS="3478,5349,19302"
# Resolvers the sandbox uid may still use (bootstrap DNS, see above).
DNS_ALLOWLIST="1.1.1.1 8.8.8.8 9.9.9.9"
# A resolver deliberately NOT on the allow-list, used by the leak probe
# to test whether an arbitrary resolver is reachable from the sandbox.
DNS_PROBE_RESOLVER="208.67.222.222"

# Ensure the dedicated sandbox user exists. Prints its uid.
sandbox_user_ensure() {
    local uid
    uid=$(id -u "$SANDBOX_USER" 2>/dev/null || true)
    if [[ -z "$uid" ]]; then
        echo -e "${CYAN}Creating system user '$SANDBOX_USER' for the sandboxes...${RESET}"
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$SANDBOX_USER" \
            || { echo -e "${RED}Could not create user $SANDBOX_USER.${RESET}"; return 1; }
        uid=$(id -u "$SANDBOX_USER" 2>/dev/null || true)
        [[ -n "$uid" ]] || { echo -e "${RED}User $SANDBOX_USER still missing after useradd.${RESET}"; return 1; }
    fi
    echo "$uid"
}

# True when the sandbox user is set up (marker file + user exists).
sandbox_user_enabled() {
    [[ -f "$SANDBOX_UID_FILE" ]] && id -u "$SANDBOX_USER" >/dev/null 2>&1
}

# One-time setup: create the user, hand it the instance folders, record
# the marker, regenerate the launchers (they pick up the `sudo -u`
# prefix from the marker) and restart the instances as that user.
# Usage: sandbox_user_setup
sandbox_user_setup() {
    local uid
    uid=$(sandbox_user_ensure) || return 1
    echo -e "${CYAN}Handing the instance folders to $SANDBOX_USER (uid $uid)...${RESET}"
    local found=0 d
    while IFS= read -r d; do
        found=1
        sudo chown -R "$SANDBOX_USER:$SANDBOX_USER" "$d" \
            || { echo -e "${RED}chown failed for $d.${RESET}"; return 1; }
    done < <(psiphon_dirs)
    [ "$found" -eq 0 ] && echo -e "${YELLOW}No psiphon-* folders yet — the user is created, folders will be chowned when created.${RESET}"
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
    printf '%s\n' "$uid" > "$SANDBOX_UID_FILE"
    echo -e "${GREEN}Sandbox user ready: $SANDBOX_USER (uid $uid). Marker: $SANDBOX_UID_FILE${RESET}"
    echo -e "${CYAN}Regenerating launchers and restarting instances as $SANDBOX_USER...${RESET}"
    generate_start_psiphon_script
    stop_all_psiphon_quiet 2>/dev/null || true
    sleep 1
    start_all_psiphon_quiet 2>/dev/null || true
}

# Print the exact firewall commands the scoped block would add,
# without applying them (dry-run / preview).
scoped_block_preview() {
    local uid
    uid=$(id -u "$SANDBOX_USER" 2>/dev/null || echo "<uid-of-$SANDBOX_USER-after-setup>")
    echo -e "${YELLOW}Scoped block preview (applies ONLY to uid $SANDBOX_USER / $uid):${RESET}"
    local ip
    for ip in $DNS_ALLOWLIST; do
        echo "  iptables -A OUTPUT -m owner --uid-owner $SANDBOX_USER -p udp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"
        echo "  iptables -A OUTPUT -m owner --uid-owner $SANDBOX_USER -p tcp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"
    done
    echo "  iptables -A OUTPUT -m owner --uid-owner $SANDBOX_USER -p udp --dport 53 -j REJECT   # all other DNS"
    echo "  iptables -A OUTPUT -m owner --uid-owner $SANDBOX_USER -p tcp --dport 53 -j REJECT   # all other DNS"
    echo "  iptables -A OUTPUT -m owner --uid-owner $SANDBOX_USER -p udp -m multiport --dports $STUN_PORTS -j REJECT   # STUN/TURN"
    echo -e "${CYAN}Xray (root), apt (root) and dig (root) do NOT match --uid-owner $SANDBOX_USER, so they keep working.${RESET}"
    if ! sandbox_user_enabled; then
        echo -e "${YELLOW}Setup needed first: create user '$SANDBOX_USER', chown the instance folders, regenerate launchers, restart instances.${RESET}"
    fi
}

# Remove any v2.0 legacy server-wide rules (same comment, no owner
# match). Best-effort; only touches rules tagged with our comment.
dns_leak_block_remove_legacy() {
    case "$(firewall_backend)" in
        iptables)
            local line rule
            while IFS= read -r line; do
                [[ "$line" == *"multifon:dns-leak-block"* ]] || continue
                [[ "$line" == *"--uid-owner"* ]] && continue
                rule="${line#-A OUTPUT }"
                # shellcheck disable=SC2086
                sudo iptables -D OUTPUT $rule >/dev/null 2>&1 || true
                echo -e "${YELLOW}Removed legacy server-wide rule:${RESET} $line"
            done < <(sudo iptables -S OUTPUT 2>/dev/null | grep -F "multifon:dns-leak-block" || true)
            ;;
        *) ;;
    esac
}

# Add the scoped DNS + STUN rules (iptables). Idempotent.
_scoped_iptables_add() {
    local ip
    # Bootstrap allow-list first: iptables takes the first match, so the
    # ACCEPTs must be added before the REJECTs.
    for ip in $DNS_ALLOWLIST; do
        _fw_iptables_add OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
        _fw_iptables_add OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p tcp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
    done
    _fw_iptables_add OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with icmp-port-unreachable
    _fw_iptables_add OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with tcp-reset
    _fw_iptables_add OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp -m multiport --dports "$STUN_PORTS" -m comment --comment "multifon:stun-block" -j REJECT --reject-with icmp-port-unreachable
}

# Remove exactly the scoped rules added above (same match args).
_scoped_iptables_del() {
    local ip
    for ip in $DNS_ALLOWLIST; do
        _fw_iptables_del OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
        _fw_iptables_del OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p tcp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
    done
    _fw_iptables_del OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with icmp-port-unreachable
    _fw_iptables_del OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with tcp-reset
    _fw_iptables_del OUTPUT -m owner --uid-owner "$SANDBOX_USER" -p udp -m multiport --dports "$STUN_PORTS" -m comment --comment "multifon:stun-block" -j REJECT --reject-with icmp-port-unreachable
}

# nft best-effort equivalent (meta skuid). Not tested on this box — the
# iptables path above is the one in use here.
_scoped_nft_add() {
    local uid ip
    uid=$(id -u "$SANDBOX_USER" 2>/dev/null || true)
    [[ -n "$uid" ]] || return 1
    for ip in $DNS_ALLOWLIST; do
        sudo nft add rule inet filter output meta skuid "$uid" ip daddr "$ip" udp dport 53 accept 2>/dev/null || true
        sudo nft add rule inet filter output meta skuid "$uid" ip daddr "$ip" tcp dport 53 accept 2>/dev/null || true
    done
    sudo nft add rule inet filter output meta skuid "$uid" udp dport 53 reject 2>/dev/null || true
    sudo nft add rule inet filter output meta skuid "$uid" tcp dport 53 reject 2>/dev/null || true
    sudo nft add rule inet filter output meta skuid "$uid" udp dport "{ $STUN_PORTS }" reject 2>/dev/null || true
}

_scoped_nft_del() {
    local uid ip
    uid=$(id -u "$SANDBOX_USER" 2>/dev/null || true)
    [[ -n "$uid" ]] || return 0
    for ip in $DNS_ALLOWLIST; do
        sudo nft delete rule inet filter output meta skuid "$uid" ip daddr "$ip" udp dport 53 accept 2>/dev/null || true
        sudo nft delete rule inet filter output meta skuid "$uid" ip daddr "$ip" tcp dport 53 accept 2>/dev/null || true
    done
    sudo nft delete rule inet filter output meta skuid "$uid" udp dport 53 reject 2>/dev/null || true
    sudo nft delete rule inet filter output meta skuid "$uid" tcp dport 53 reject 2>/dev/null || true
    sudo nft delete rule inet filter output meta skuid "$uid" udp dport "{ $STUN_PORTS }" reject 2>/dev/null || true
}

# Enable the scoped DNS + STUN blocks (used by lib/dns.sh).
# Removes v2.0 legacy server-wide rules first.
dns_leak_block_enable() {
    if ! sandbox_user_enabled; then
        echo -e "${YELLOW}First-time setup: the instances must run as the '$SANDBOX_USER' user for the scoped rules to match them.${RESET}"
        sandbox_user_setup || return 1
    fi
    dns_leak_block_remove_legacy
    case "$(firewall_backend)" in
        iptables)
            _scoped_iptables_add
            echo -e "${GREEN}Scoped DNS block on: only $SANDBOX_USER is affected (bootstrap DNS to $DNS_ALLOWLIST still allowed).${RESET}"
            echo -e "${GREEN}Scoped STUN block on: UDP $STUN_PORTS REJECTed for $SANDBOX_USER.${RESET}"
            ;;
        nft)
            _scoped_nft_add
            echo -e "${GREEN}Scoped DNS + STUN block on via nft (best-effort, untested here).${RESET}"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

# Disable: removes exactly what enable added (tagged rules only).
dns_leak_block_disable() {
    case "$(firewall_backend)" in
        iptables)
            _scoped_iptables_del
            dns_leak_block_remove_legacy
            echo -e "${GREEN}Scoped DNS + STUN block off (only multifon-tagged rules removed).${RESET}"
            ;;
        nft)
            _scoped_nft_del
            echo -e "${GREEN}Scoped DNS + STUN block off (nft).${RESET}"
            ;;
        *) ;;
    esac
}

# Status of the scoped DNS block: blocked / open / unknown.
dns_leak_block_status() {
    case "$(firewall_backend)" in
        iptables)
            if sudo iptables -S OUTPUT 2>/dev/null | grep -q "multifon:dns-leak-block.*--uid-owner"; then
                echo "blocked (scoped, uid $SANDBOX_USER)"
            elif sudo iptables -S OUTPUT 2>/dev/null | grep -q "multifon:dns-leak-block"; then
                echo "blocked (LEGACY server-wide — remove it: re-enable once to migrate)"
            else
                echo "open"
            fi
            ;;
        nft)
            if sudo nft list ruleset 2>/dev/null | grep -q "dport 53 reject"; then
                echo "blocked"
            else
                echo "open"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# Status of the scoped STUN block: blocked / open / unknown.
# Honest limit: this only affects traffic that reaches the server. In
# proxy-only client mode the browser's STUN UDP never reaches the server,
# so the client still needs TUN mode or the Chromium flag
# --force-webrtc-ip-handling-policy=disable_non_proxied_udp.
stun_block_status() {
    case "$(firewall_backend)" in
        iptables)
            if sudo iptables -S OUTPUT 2>/dev/null | grep -q "multifon:stun-block"; then
                echo "blocked (scoped, uid $SANDBOX_USER; server-side only — see comment in lib/firewall.sh)"
            else
                echo "open"
            fi
            ;;
        nft)
            if sudo nft list ruleset 2>/dev/null | grep -q "3478"; then
                echo "blocked"
            else
                echo "open"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}
