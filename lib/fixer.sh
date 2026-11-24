#!/bin/bash
# multifon v2.1 — lib/fixer.sh
# `multifon fix`: runs the docs/SERVICES.md checklist against every
# instance and fixes what can be fixed server-side.
# It REUSES health_check_all (lib/doctor.sh) and dns_leak_check
# (lib/dns.sh) — nothing is duplicated here; this file only drives them,
# reads their output, and acts on it.
# What it cannot fix it prints as a client-side checklist at the end:
# browser timezone and the Chromium WebRTC flag / TUN mode live on the
# user's own machine, not on this server.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_FIXER_LOADED:-}" ]] && return 0
_MULTIFON_FIXER_LOADED=1

# Print the remaining client-side steps (from docs/SERVICES.md).
fixer_client_checklist() {
    echo ""
    echo -e "${YELLOW}Remaining steps — client-side, the server cannot do these:${RESET}"
    echo -e " [ ] Browser timezone: set the browser/OS timezone to the exit country"
    echo -e "     (IPFighter compares the exact IANA zone name). Server-side fix: none —"
    echo -e "     the sandbox TZ set per egress only affects the psiphon process itself."
    echo -e " [ ] WebRTC leak: use TUN mode in the client, or start Chromium with"
    echo -e "     --force-webrtc-ip-handling-policy=disable_non_proxied_udp"
    echo -e "     (the server STUN block only catches traffic that reaches the server)."
    echo -e " [ ] Language: Accept-Language / browser language matching the exit country."
    echo -e " [ ] Non-residential -10%: not fixable — Psiphon/WARP/Tor exits are datacenter IPs."
    echo -e " Honest ceiling with everything server-side fixed: good IP 60% -> 75%"
    echo -e " (100 - 15 timezone - 10 non-residential)."
}

# Entry point: `multifon fix` or main menu 11.
multifon_fix() {
    echo -e "${CYAN}${BOLD}multifon fix — server-side checklist${RESET}"
    echo -e "Fixes what the server can fix; prints the rest as a checklist."
    echo ""

    # 0) Repair drift first (orphan registry/INFO entries, stale units).
    echo -e "${YELLOW}[0/4] Doctor sync...${RESET}"
    doctor_sync
    echo ""

    # 1) Health check per instance (exit IP + latency + blacklist).
    echo -e "${YELLOW}[1/4] Health check (exit IP + latency + blacklist)...${RESET}"
    local hc_out
    hc_out=$(mktemp)
    health_check_all | tee "$hc_out"
    echo ""

    # 2) Rotate any instance whose IP is listed (with confirmation).
    echo -e "${YELLOW}[2/4] Dirty IPs...${RESET}"
    local dirty
    # Strip ANSI colors first: health-check lines are colorized.
    dirty=$(sed 's/\x1b\[[0-9;]*m//g' "$hc_out" | grep "LISTED on" | awk '{print $1}' | sort -u || true)
    if [[ -z "$dirty" ]]; then
        echo -e " ${GREEN}No listed exit IPs found.${RESET}"
    else
        local name d
        for name in $dirty; do
            d="$PSIPHON_BASE_DIR/psiphon/$name"
            [ -d "$d" ] || continue
            echo -e " ${RED}$name is blacklisted.${RESET}"
            if confirm_yes "Rotate its IP now?"; then
                rotate_ip "$d" || true
            else
                echo -e " ${YELLOW}Left as-is: $name${RESET}"
            fi
        done
    fi
    rm -f "$hc_out"
    echo ""

    # 3) DNS leak check per instance + scoped blocks.
    echo -e "${YELLOW}[3/4] DNS leak check + scoped blocks...${RESET}"
    dns_leak_check_all || true
    echo ""
    echo -e " Scoped DNS block: $(dns_leak_block_status)"
    echo -e " Scoped STUN block: $(stun_block_status)"
    if [[ "$(dns_leak_block_status)" == "open" ]]; then
        echo -e " ${YELLOW}The scoped port-53 + STUN block is off.${RESET}"
        if confirm_yes "Enable it now (sandbox user only — Xray keeps working)?"; then
            dns_force_enable || true
        fi
    fi
    echo ""

    # 4) The part no server command can do.
    echo -e "${YELLOW}[4/4] Client-side remainder...${RESET}"
    fixer_client_checklist
    echo ""
    echo -e "${GREEN}multifon fix done. Re-run the IPFighter test to see the new score.${RESET}"
}
