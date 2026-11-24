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
# v2.3 — this REPLACES the v2.1 uid-owner block (and the v2.0 server-wide
# block before it). Why v2.0 was wrong: Xray's own DNS uses plain
# 1.1.1.1 / 9.9.9.9 on port 53, so a server-wide block kills DNS for
# every 3x-ui config, plus apt and dig on the server. The user caught
# this live (menu 8 warned about it, and he cancelled with Ctrl+C).
#
# Mechanism: iptables owner match (-m owner --gid-owner) on the shared
# group `multifon`. Every Psiphon instance runs as its own system user
# (multifon-<cc>) in that group — one systemd unit per instance, see
# lib/systemd.sh — so the OUTPUT rules match all instances with one
# rule set, and nothing else. Xray runs as root, apt runs as root, dig
# runs as root — none of them match, so they keep working.
# Why not the alternatives: a server-wide OUTPUT rule breaks Xray (see
# above); a per-uid rule set would need one rule per instance user and
# would rot whenever an instance is added or deleted; the old
# per-sandbox netfilter approach is gone (systemd units + gid-owner
# rules replaced it in v2.3).
#
# One deliberate exception — the bootstrap allow-list: the Psiphon core
# itself needs DNS to fetch its remote server list at startup, so the
# instance users may still query 1.1.1.1, 8.8.8.8 and 9.9.9.9 on port 53.
# Everything ELSE on port 53 for that gid is REJECTed. That stops leaks
# to arbitrary / ISP resolvers (the country-mismatch case). The full
# "no direct DNS at all" variant is the per-egress DoH forwarder
# (dnscrypt-proxy, lib/dns.sh) — it exists since v2.2.
# STUN needs no exception: the core never uses STUN. The STUN rule
# therefore REJECTs all three ports for the group, no allow-list.
#
# The rules use REJECT (fail fast) instead of DROP, so a blocked query
# fails immediately instead of hanging until timeout.
# Enabling the scoped block the first time creates the `multifon` group,
# ensures every instance has its own user + unit, and restarts the
# running instances as their users. "Disable" removes exactly the
# tagged rules that "enable" added — nothing else. Enabling also removes
# any v2.0 (server-wide) or v2.1 (--uid-owner multifon) legacy rules.

# The shared group lives in lib/systemd.sh (SANDBOX_GROUP); the marker
# file too (SANDBOX_GID_FILE). The legacy v2.1 single-user marker is
# SANDBOX_UID_FILE_LEGACY there. This file only uses them.
STUN_PORTS="3478,5349,19302"
# Resolvers the sandbox uid may still use (bootstrap DNS, see above).
DNS_ALLOWLIST="1.1.1.1 8.8.8.8 9.9.9.9"
# A resolver deliberately NOT on the allow-list, used by the leak probe
# to test whether an arbitrary resolver is reachable from the sandbox.
DNS_PROBE_RESOLVER="208.67.222.222"

# One-time setup: ensure the group exists, drop the legacy v2.1
# marker, make sure every instance runs as its own user in the group
# (unit + user per folder), and restart the ones that were running so
# they run as their users from now on.
# Usage: sandbox_group_setup
sandbox_group_setup() {
    local gid
    gid=$(systemd_group_ensure) || return 1
    rm -f "$SANDBOX_UID_FILE_LEGACY"
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
    printf '%s\n' "$gid" > "$SANDBOX_GID_FILE"
    echo -e "${GREEN}Sandbox group ready: $SANDBOX_GROUP (gid $gid). Marker: $SANDBOX_GID_FILE${RESET}"
    echo -e "${CYAN}Ensuring every instance has its own user + unit...${RESET}"
    local d was_running
    while IFS= read -r d; do
        was_running=0
        psiphon_live_pid "$d" >/dev/null 2>&1 && was_running=1
        # Stop the old (non-unit) process first, or the unit cannot bind
        # the same ports afterwards.
        stop_psiphon_in_dir "$d" 2>/dev/null || true
        systemd_unit_ensure "$d" || { echo -e "${RED}Could not set up $(basename "$d").${RESET}"; return 1; }
        if [[ "$was_running" -eq 1 ]]; then
            systemd_instance_start "$d" || echo -e "${YELLOW}$(basename "$d") did not start — check: systemctl status $(systemd_unit_name "$d")${RESET}"
        fi
    done < <(psiphon_dirs)
}

# Print the exact firewall commands the scoped block would add,
# without applying them (dry-run / preview).
scoped_block_preview() {
    local gid
    gid=$(getent group "$SANDBOX_GROUP" 2>/dev/null | cut -d: -f3 || echo "<gid-of-$SANDBOX_GROUP-after-setup>")
    echo -e "${YELLOW}Scoped block preview (applies ONLY to group $SANDBOX_GROUP / $gid):${RESET}"
    local ip
    for ip in $DNS_ALLOWLIST; do
        echo "  iptables -A OUTPUT -m owner --gid-owner $SANDBOX_GROUP -p udp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"
        echo "  iptables -A OUTPUT -m owner --gid-owner $SANDBOX_GROUP -p tcp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"
    done
    echo "  iptables -A OUTPUT -m owner --gid-owner $SANDBOX_GROUP -p udp --dport 53 -j REJECT   # all other DNS"
    echo "  iptables -A OUTPUT -m owner --gid-owner $SANDBOX_GROUP -p tcp --dport 53 -j REJECT   # all other DNS"
    echo "  iptables -A OUTPUT -m owner --gid-owner $SANDBOX_GROUP -p udp -m multiport --dports $STUN_PORTS -j REJECT   # STUN/TURN"
    echo -e "${CYAN}Xray (root), apt (root) and dig (root) do NOT match --gid-owner $SANDBOX_GROUP, so they keep working.${RESET}"
    if ! sandbox_group_enabled; then
        echo -e "${YELLOW}Setup needed first: create group '$SANDBOX_GROUP', ensure every instance has its own user + unit, restart the running ones.${RESET}"
    fi
}

# Remove any legacy rules with our comment tags that are NOT gid-owner:
# v2.0 server-wide rules (no owner match at all) and v2.1 rules
# (--uid-owner multifon). Best-effort; only touches our tagged rules.
dns_leak_block_remove_legacy() {
    case "$(firewall_backend)" in
        iptables)
            local line rule
            while IFS= read -r line; do
                [[ "$line" == *"multifon:dns-leak-block"* || "$line" == *"multifon:stun-block"* ]] || continue
                [[ "$line" == *"--gid-owner"* ]] && continue
                rule="${line#-A OUTPUT }"
                # shellcheck disable=SC2086
                sudo iptables -D OUTPUT $rule >/dev/null 2>&1 || true
                echo -e "${YELLOW}Removed legacy rule:${RESET} $line"
            done < <(sudo iptables -S OUTPUT 2>/dev/null | grep -F -e "multifon:dns-leak-block" -e "multifon:stun-block" || true)
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
        _fw_iptables_add OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
        _fw_iptables_add OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p tcp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
    done
    _fw_iptables_add OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with icmp-port-unreachable
    _fw_iptables_add OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with tcp-reset
    _fw_iptables_add OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp -m multiport --dports "$STUN_PORTS" -m comment --comment "multifon:stun-block" -j REJECT --reject-with icmp-port-unreachable
}

# Remove exactly the scoped rules added above (same match args).
_scoped_iptables_del() {
    local ip
    for ip in $DNS_ALLOWLIST; do
        _fw_iptables_del OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
        _fw_iptables_del OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p tcp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT
    done
    _fw_iptables_del OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with icmp-port-unreachable
    _fw_iptables_del OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with tcp-reset
    _fw_iptables_del OUTPUT -m owner --gid-owner "$SANDBOX_GROUP" -p udp -m multiport --dports "$STUN_PORTS" -m comment --comment "multifon:stun-block" -j REJECT --reject-with icmp-port-unreachable
}

# nft best-effort equivalent (meta skgid). Not tested on this box — the
# iptables path above is the one in use here.
_scoped_nft_add() {
    local gid ip
    gid=$(getent group "$SANDBOX_GROUP" 2>/dev/null | cut -d: -f3 || true)
    [[ -n "$gid" ]] || return 1
    for ip in $DNS_ALLOWLIST; do
        sudo nft add rule inet filter output meta skgid "$gid" ip daddr "$ip" udp dport 53 accept 2>/dev/null || true
        sudo nft add rule inet filter output meta skgid "$gid" ip daddr "$ip" tcp dport 53 accept 2>/dev/null || true
    done
    sudo nft add rule inet filter output meta skgid "$gid" udp dport 53 reject 2>/dev/null || true
    sudo nft add rule inet filter output meta skgid "$gid" tcp dport 53 reject 2>/dev/null || true
    sudo nft add rule inet filter output meta skgid "$gid" udp dport "{ $STUN_PORTS }" reject 2>/dev/null || true
}

_scoped_nft_del() {
    local gid ip
    gid=$(getent group "$SANDBOX_GROUP" 2>/dev/null | cut -d: -f3 || true)
    [[ -n "$gid" ]] || return 0
    for ip in $DNS_ALLOWLIST; do
        sudo nft delete rule inet filter output meta skgid "$gid" ip daddr "$ip" udp dport 53 accept 2>/dev/null || true
        sudo nft delete rule inet filter output meta skgid "$gid" ip daddr "$ip" tcp dport 53 accept 2>/dev/null || true
    done
    sudo nft delete rule inet filter output meta skgid "$gid" udp dport 53 reject 2>/dev/null || true
    sudo nft delete rule inet filter output meta skgid "$gid" tcp dport 53 reject 2>/dev/null || true
    sudo nft delete rule inet filter output meta skgid "$gid" udp dport "{ $STUN_PORTS }" reject 2>/dev/null || true
}

# Enable the scoped DNS + STUN blocks (used by lib/dns.sh).
# Removes v2.0 legacy server-wide rules first.
dns_leak_block_enable() {
    if ! sandbox_group_enabled; then
        echo -e "${YELLOW}First-time setup: the instances must run as users in the '$SANDBOX_GROUP' group for the scoped rules to match them.${RESET}"
        sandbox_group_setup || return 1
    fi
    dns_leak_block_remove_legacy
    case "$(firewall_backend)" in
        iptables)
            _scoped_iptables_add
            echo -e "${GREEN}Scoped DNS block on: only group $SANDBOX_GROUP is affected (bootstrap DNS to $DNS_ALLOWLIST still allowed).${RESET}"
            echo -e "${GREEN}Scoped STUN block on: UDP $STUN_PORTS REJECTed for group $SANDBOX_GROUP.${RESET}"
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

# _scoped_block_kind <tag> -> open | scoped | legacy | both
# v2.3.1 fix: the old classifier grepped for
# "multifon:dns-leak-block.*--gid-owner", but in `iptables -S` output
# the --gid-owner match comes BEFORE the comment tag
# (-A OUTPUT -m owner --gid-owner multifon ... -m comment --comment
# "multifon:dns-leak-block"), so that pattern could NEVER match and
# every scoped block was misreported as LEGACY — while the enable path
# had installed the correct gid-owner rules all along. Now the tag
# lines are collected first, then split by --gid-owner.
_scoped_block_kind() {
    local tag="$1" rules
    rules=$(sudo iptables -S OUTPUT 2>/dev/null | grep -F "$tag" || true)
    [[ -z "$rules" ]] && { echo "open"; return 0; }
    local has_gid=0 has_other=0
    echo "$rules" | grep -q -- "--gid-owner" && has_gid=1
    echo "$rules" | grep -vq -- "--gid-owner" && has_other=1
    if [[ "$has_gid" -eq 1 && "$has_other" -eq 1 ]]; then echo "both"
    elif [[ "$has_gid" -eq 1 ]]; then echo "scoped"
    else echo "legacy"; fi
}

# True when tagged legacy rules (uid-owner or server-wide, no gid-owner)
# are present — used by doctor_sync.
firewall_legacy_rules_present() {
    case "$(firewall_backend)" in
        iptables)
            local rules
            rules=$(sudo iptables -S OUTPUT 2>/dev/null | grep -F -e "multifon:dns-leak-block" -e "multifon:stun-block" || true)
            [[ -z "$rules" ]] && return 1
            echo "$rules" | grep -vq -- "--gid-owner"
            ;;
        *) return 1 ;;
    esac
}

# Status of the scoped DNS block: blocked / open / unknown.
dns_leak_block_status() {
    case "$(firewall_backend)" in
        iptables)
            case "$(_scoped_block_kind "multifon:dns-leak-block")" in
                scoped) echo "blocked (scoped, gid $SANDBOX_GROUP)" ;;
                legacy) echo "blocked (LEGACY uid-owner/server-wide — remove it: re-enable once to migrate)" ;;
                both) echo "blocked (scoped, gid $SANDBOX_GROUP) + LEGACY rules also present — re-enable once to remove them" ;;
                *) echo "open" ;;
            esac
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
            case "$(_scoped_block_kind "multifon:stun-block")" in
                scoped) echo "blocked (scoped, gid $SANDBOX_GROUP; server-side only — see comment in lib/firewall.sh)" ;;
                legacy) echo "blocked (LEGACY uid-owner — remove it: re-enable once to migrate)" ;;
                both) echo "blocked (scoped, gid $SANDBOX_GROUP) + LEGACY rules also present — re-enable once to remove them" ;;
                *) echo "open" ;;
            esac
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
