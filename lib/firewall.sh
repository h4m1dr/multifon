#!/bin/bash
# multifon v2 — lib/firewall.sh
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
            ;;
        nft)
            echo -e "${YELLOW}nft ruleset (grep multifon ports manually):${RESET}"
            sudo nft list ruleset 2>/dev/null | grep -E 'dport|drop|accept' || echo -e " (none)"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

# --- DNS-leak enforcement (used by lib/dns.sh) -------------------------
# Block direct outbound DNS (UDP/TCP 53) so nothing on the box can leak
# DNS around the proxy. This is OFF by default and needs a deliberate
# enable: it also blocks plain `dig`/`nslookup` from the shell.
# Usage: dns_leak_block_enable / dns_leak_block_disable / dns_leak_block_status

dns_leak_block_enable() {
    case "$(firewall_backend)" in
        iptables)
            _fw_iptables_add OUTPUT -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j DROP
            _fw_iptables_add OUTPUT -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j DROP
            echo -e "${GREEN}Direct outbound DNS (port 53) is now blocked. DNS must go through the proxy (DoH).${RESET}"
            ;;
        nft)
            sudo nft add rule inet filter output udp dport 53 drop 2>/dev/null
            sudo nft add rule inet filter output tcp dport 53 drop 2>/dev/null
            echo -e "${GREEN}Direct outbound DNS (port 53) blocked via nft.${RESET}"
            ;;
        *)
            echo -e "${RED}No firewall tool found (need iptables or nft).${RESET}"
            return 1
            ;;
    esac
}

dns_leak_block_disable() {
    case "$(firewall_backend)" in
        iptables)
            _fw_iptables_del OUTPUT -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j DROP
            _fw_iptables_del OUTPUT -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j DROP
            echo -e "${GREEN}Direct outbound DNS (port 53) is allowed again.${RESET}"
            ;;
        nft)
            sudo nft delete rule inet filter output udp dport 53 drop 2>/dev/null || true
            sudo nft delete rule inet filter output tcp dport 53 drop 2>/dev/null || true
            echo -e "${GREEN}Direct outbound DNS (port 53) allowed again (nft).${RESET}"
            ;;
        *) ;;
    esac
}

dns_leak_block_status() {
    case "$(firewall_backend)" in
        iptables)
            if sudo iptables -S OUTPUT 2>/dev/null | grep -q "multifon:dns-leak-block"; then
                echo "blocked"
            else
                echo "open"
            fi
            ;;
        nft)
            if sudo nft list ruleset 2>/dev/null | grep -q "dport 53 drop"; then
                echo "blocked"
            else
                echo "open"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}
