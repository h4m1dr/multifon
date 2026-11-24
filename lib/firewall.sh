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

_fw_iptables_insert() {
    # _fw_iptables_insert <chain> <position> <rule...>
    # Insert at an exact position (used by the scoped block: the rules
    # must sit ABOVE any earlier ACCEPT — see _scoped_iptables_add).
    # Idempotent: an identical rule anywhere in the chain is left alone.
    local chain="$1" pos="$2"; shift 2
    _fw_iptables_has "$chain" "$@" && return 0
    sudo iptables -I "$chain" "$pos" "$@"
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
#
# v2.3.3 — PLACEMENT (confirmed live 2026-11-24 with the full chain +
# counters): the rules were correct but APPENDED (-A) at the END of
# OUTPUT, AFTER UFW's jumps (ufw-before-output etc.). UFW's
# before-output chain ACCEPTs ~everything, so only a fraction of
# packets ever returns to the main chain — all multifon rules showed
# 0 packets / 0 bytes and the REJECT counters stayed 0 after a dig as
# multifon-nl. The leak was real; the placement was wrong. The block
# is now INSERTED at the very TOP of OUTPUT (position 1, before the
# UFW jumps), bootstrap ACCEPTs first, then the REJECTs. Rules live
# only in the running firewall: a reboot or `ufw reload` wipes OUTPUT,
# so enabling also installs a oneshot unit (multifon-firewall.service)
# that re-applies them at boot, and doctor_sync re-applies them when
# it finds them gone — or sitting below the UFW jumps.

# The shared group lives in lib/systemd.sh (SANDBOX_GROUP); the marker
# file too (SANDBOX_GID_FILE). The legacy v2.1 single-user marker is
# SANDBOX_UID_FILE_LEGACY there. This file only uses them.
STUN_PORTS="3478,5349,19302"
# Oneshot unit that re-applies this block at boot (see below).
FIREWALL_ONESHOT_UNIT="multifon-firewall.service"
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
    echo -e "${YELLOW}Scoped block preview (inserted at the TOP of OUTPUT — position 1, BEFORE the UFW jumps; applies ONLY to group $SANDBOX_GROUP / $gid):${RESET}"
    local ip pos=1
    for ip in $DNS_ALLOWLIST; do
        echo "  iptables -I OUTPUT $pos -m owner --gid-owner $SANDBOX_GROUP -p udp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"; pos=$((pos+1))
        echo "  iptables -I OUTPUT $pos -m owner --gid-owner $SANDBOX_GROUP -p tcp -d $ip --dport 53 -j ACCEPT   # bootstrap DNS"; pos=$((pos+1))
    done
    echo "  iptables -I OUTPUT $pos -m owner --gid-owner $SANDBOX_GROUP -p udp --dport 53 -j REJECT   # all other DNS"; pos=$((pos+1))
    echo "  iptables -I OUTPUT $pos -m owner --gid-owner $SANDBOX_GROUP -p tcp --dport 53 -j REJECT   # all other DNS"; pos=$((pos+1))
    echo "  iptables -I OUTPUT $pos -m owner --gid-owner $SANDBOX_GROUP -p udp -m multiport --dports $STUN_PORTS -j REJECT   # STUN/TURN"
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
# v2.3.3: INSERT at the TOP of OUTPUT (positions 1..9), never append.
# Appended rules sat BELOW UFW's jumps and were never evaluated (all
# counters 0 while 63M packets went through ufw-before-output). The
# block only matches gid $SANDBOX_GROUP, so top placement affects
# nothing else. Bootstrap ACCEPTs go in first, then the REJECTs —
# iptables takes the first match, so the order is the whole point.
_scoped_iptables_add() {
    local ip pos=1
    for ip in $DNS_ALLOWLIST; do
        _fw_iptables_insert OUTPUT "$pos" -m owner --gid-owner "$SANDBOX_GROUP" -p udp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT; pos=$((pos+1))
        _fw_iptables_insert OUTPUT "$pos" -m owner --gid-owner "$SANDBOX_GROUP" -p tcp -d "$ip" --dport 53 -m comment --comment "multifon:dns-leak-block" -j ACCEPT; pos=$((pos+1))
    done
    _fw_iptables_insert OUTPUT "$pos" -m owner --gid-owner "$SANDBOX_GROUP" -p udp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with icmp-port-unreachable; pos=$((pos+1))
    _fw_iptables_insert OUTPUT "$pos" -m owner --gid-owner "$SANDBOX_GROUP" -p tcp --dport 53 -m comment --comment "multifon:dns-leak-block" -j REJECT --reject-with tcp-reset; pos=$((pos+1))
    _fw_iptables_insert OUTPUT "$pos" -m owner --gid-owner "$SANDBOX_GROUP" -p udp -m multiport --dports "$STUN_PORTS" -m comment --comment "multifon:stun-block" -j REJECT --reject-with icmp-port-unreachable; pos=$((pos+1))
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

# _scoped_reject_pkts — sum of the packet counters of the two DNS REJECT
# rules (udp + tcp). Prints 0 when the rules are absent or unreadable.
# (`iptables -L` shows the rule comment as /* multifon:... */.)
_scoped_reject_pkts() {
    sudo iptables -L OUTPUT -v -n -x 2>/dev/null \
        | grep "multifon:dns-leak-block" | grep "REJECT" \
        | awk '{s+=$1} END {print s+0}'
}

# _scoped_block_below_ufw — true when the first multifon DNS rule sits
# BELOW a UFW jump in OUTPUT, i.e. UFW ACCEPTs the traffic before our
# rules are ever evaluated. (The v2.3.1 placement: rules 7-15, UFW
# jumps 1-6, all multifon counters 0.)
_scoped_block_below_ufw() {
    local out first_mf first_ufw
    out=$(sudo iptables -S OUTPUT 2>/dev/null || true)
    [[ -n "$out" ]] || return 1
    first_mf=$(echo "$out" | grep -n -F "multifon:dns-leak-block" | head -n1 | cut -d: -f1)
    first_ufw=$(echo "$out" | grep -n -F "ufw-before-output" | head -n1 | cut -d: -f1)
    [[ -n "$first_mf" && -n "$first_ufw" && "$first_ufw" -lt "$first_mf" ]]
}

# dns_leak_block_selftest — prove the block actually catches traffic.
# Reads the DNS REJECT counters, runs one direct-DNS probe as the first
# instance user (with the unit's gid), reads the counters again.
#   0 = block works (counter moved, probe REJECTed)
#   1 = LEAK (probe answered — the block is not catching this traffic)
#   2 = inconclusive (no answer, counter did not move — probe failed
#       for another reason, e.g. no route; check counters by hand)
# Never silent: it always prints what it found.
dns_leak_block_selftest() {
    local user before after
    user=$(systemd_first_instance_user || true)
    if [[ -z "$user" ]]; then
        echo -e " ${YELLOW}Self-test skipped — no instance user yet (no instances).${RESET}"
        return 2
    fi
    command -v dig >/dev/null 2>&1 || {
        echo -e " ${YELLOW}Self-test skipped — dig is not installed.${RESET}"
        return 2
    }
    before=$(_scoped_reject_pkts)
    if timeout 5 sudo -u "$user" -g "$SANDBOX_GROUP" dig +short +time=3 +tries=1 "@$DNS_PROBE_RESOLVER" example.com >/dev/null 2>&1; then
        after=$(_scoped_reject_pkts)
        echo -e " ${RED}SELF-TEST FAILED: direct DNS as $user (@$DNS_PROBE_RESOLVER) still answers, REJECT counter $before -> $after — the block is NOT catching traffic. Check rule order: sudo iptables -L OUTPUT -n -v --line-numbers (the multifon rules must sit ABOVE the UFW jumps).${RESET}"
        return 1
    fi
    after=$(_scoped_reject_pkts)
    if [[ "${after:-0}" -gt "${before:-0}" ]]; then
        echo -e " ${GREEN}Self-test OK: direct DNS as $user is REJECTed (REJECT counter $before -> $after).${RESET}"
        return 0
    fi
    echo -e " ${YELLOW}Self-test inconclusive: probe got no answer but the REJECT counter did not move ($before -> $after) — the probe may have failed for another reason (no route?). Check counters by hand: sudo iptables -L OUTPUT -n -v.${RESET}"
    return 2
}

# Boot-time durability: iptables rules live only in the running
# firewall — a reboot or `ufw reload` wipes OUTPUT, so the block would
# silently disappear. Enabling installs this oneshot unit, which
# re-applies the rules at boot (before the instances need them).
# The unit file itself is the "block is enabled" marker: disabling
# (or nuke) removes it again.
firewall_oneshot_install() {
    local unit="$SYSTEMD_UNIT_DIR/$FIREWALL_ONESHOT_UNIT" tmp
    tmp=$(mktemp) || return 1
    {
        printf '%s\n' "[Unit]"
        printf '%s\n' "Description=multifon: re-apply scoped DNS/STUN block (OUTPUT is wiped by reboot / ufw reload)"
        printf '%s\n' "After=network-online.target"
        printf '%s\n' "Wants=network-online.target"
        printf '%s\n' ""
        printf '%s\n' "[Service]"
        printf '%s\n' "Type=oneshot"
        printf 'ExecStart=%s/multifon.sh reapply-block\n' "$MULTIFON_DIR"
        printf '%s\n' "RemainAfterExit=yes"
        printf '%s\n' ""
        printf '%s\n' "[Install]"
        printf '%s\n' "WantedBy=multi-user.target"
    } > "$tmp"
    sudo install -m 0644 "$tmp" "$unit"
    rm -f "$tmp"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable "$FIREWALL_ONESHOT_UNIT" >/dev/null 2>&1 || true
}

firewall_oneshot_remove() {
    sudo systemctl disable --now "$FIREWALL_ONESHOT_UNIT" >/dev/null 2>&1 || true
    sudo rm -f "$SYSTEMD_UNIT_DIR/$FIREWALL_ONESHOT_UNIT"
    sudo systemctl daemon-reload 2>/dev/null || true
}

# dns_leak_block_reapply — boot-time re-apply (multifon-firewall.service)
# and the repair path for rules that went missing or ended up below the
# UFW jumps. Deletes any existing scoped rules first, then re-inserts
# them at the top. Idempotent; safe to run any time the group exists.
dns_leak_block_reapply() {
    sandbox_group_enabled || return 0
    case "$(firewall_backend)" in
        iptables)
            _scoped_iptables_del
            _scoped_iptables_add
            # Also (re-)install the boot unit, so a repair by doctor does
            # not leave the block unprotected against the next reboot.
            firewall_oneshot_install
            echo "Scoped DNS + STUN block re-applied (top of OUTPUT)."
            ;;
        *)
            echo "reapply-block: no iptables backend — nothing done."
            ;;
    esac
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
            # Delete any existing scoped rules first: a v2.3.1 install
            # left them APPENDED below the UFW jumps, and the insert
            # below skips rules that already exist anywhere — without
            # this the re-enable would leave them dead.
            _scoped_iptables_del
            _scoped_iptables_add
            firewall_oneshot_install
            echo -e "${GREEN}Scoped DNS block on: only group $SANDBOX_GROUP is affected (bootstrap DNS to $DNS_ALLOWLIST still allowed).${RESET}"
            echo -e "${GREEN}Scoped STUN block on: UDP $STUN_PORTS REJECTed for group $SANDBOX_GROUP.${RESET}"
            echo -e "${CYAN}Rules inserted at the TOP of OUTPUT (above the UFW jumps) + oneshot unit $FIREWALL_ONESHOT_UNIT installed, so a reboot or 'ufw reload' re-applies them.${RESET}"
            dns_leak_block_selftest || true
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
            firewall_oneshot_remove
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
                scoped)
                    if _scoped_block_below_ufw; then
                        echo "blocked (scoped, gid $SANDBOX_GROUP) — BUT the rules sit BELOW the UFW jumps, so UFW ACCEPTs the traffic first; re-enable once to move them to the top"
                    else
                        echo "blocked (scoped, gid $SANDBOX_GROUP)"
                    fi
                    ;;
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
                scoped)
                    if _scoped_block_below_ufw; then
                        echo "blocked (scoped, gid $SANDBOX_GROUP; server-side only) — BUT the rules sit BELOW the UFW jumps; re-enable once to move them to the top"
                    else
                        echo "blocked (scoped, gid $SANDBOX_GROUP; server-side only — see comment in lib/firewall.sh)"
                    fi
                    ;;
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
