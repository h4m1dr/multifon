#!/bin/bash
# multifon v2 — lib/doctor.sh
# Doctor / sync + health checks.
# Fixes bugs #5 and #6: state is reconciled from the LIVE process and the
# real folders on disk, not from pidfiles and registry files alone.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_DOCTOR_LOADED:-}" ]] && return 0
_MULTIFON_DOCTOR_LOADED=1

# Print the PID of the live Psiphon process for one instance folder.
# Matches the core process whose working directory IS the folder, or the
# firejail parent whose --private= points at it. Prints nothing + returns 1
# when the instance is not running.
psiphon_live_pid() {
    local d="$1" pid="" cwd=""
    command -v pgrep >/dev/null 2>&1 || return 1
    # 1) the tunnel core itself (its cwd is the instance folder)
    for pid in $(pgrep -f "psiphon-tunnel-core" 2>/dev/null || true); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
        if [[ "$cwd" == "$d" ]]; then
            echo "$pid"
            return 0
        fi
    done
    # 2) the firejail parent (its cmdline contains --private=<dir>)
    for pid in $(pgrep -f "firejail.*--private" 2>/dev/null || true); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "--private=$d"; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# Reconcile ONE folder's pidfile with reality:
#  - pidfile exists but the PID is dead  -> remove the stale pidfile
#  - process is alive but no pidfile    -> write the pidfile
#  - both agree                          -> nothing to do
doctor_reconcile_pidfile() {
    local d="$1" pid="" live=""
    if [ -f "$d/psiphon.firejail.pid" ]; then
        pid=$(cat "$d/psiphon.firejail.pid" 2>/dev/null || true)
        if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
            echo -e " ${YELLOW}stale pidfile removed:${RESET} $(basename "$d") (was $pid)"
            rm -f "$d/psiphon.firejail.pid"
            pid=""
        fi
    fi
    live=$(psiphon_live_pid "$d" || true)
    if [[ -n "$live" && ! -f "$d/psiphon.firejail.pid" ]]; then
        echo "$live" > "$d/psiphon.firejail.pid"
        echo -e " ${GREEN}pidfile repaired:${RESET} $(basename "$d") (live pid $live)"
    fi
}

# doctor_sync — the canonical repair pass (bugs #1/#5/#6).
#  - registry entries whose folder is gone     -> prune entry + INFO block
#  - INFO blocks whose folder is gone          -> prune block
#  - folders with no registry entry            -> re-register from config.json
#  - stale / missing pidfiles                  -> reconcile from live process
#  - ports the registry claims but nobody holds -> report as free again
doctor_sync() {
    echo -e "${YELLOW}Doctor: syncing registry + INFO + folders + pidfiles...${RESET}"
    local fixed=0
    port_registry_init

    # 1) prune registry entries whose folder is gone
    local name http socks
    while read -r name http socks; do
        [[ -z "$name" ]] && continue
        if [[ ! -d "$PSIPHON_BASE_DIR/psiphon/$name" ]]; then
            echo -e " ${YELLOW}orphan registry entry removed:${RESET} $name (folder gone, ports $http/$socks freed)"
            port_registry_del_entry "$name"
            info_remove_block "$name"
            fixed=$((fixed + 1))
        fi
    done < "$PORT_REG_FILE"

    # 2) prune INFO blocks whose folder is gone
    local blk
    for blk in $(info_list_blocks); do
        if [[ ! -d "$PSIPHON_BASE_DIR/psiphon/$blk" ]]; then
            echo -e " ${YELLOW}orphan INFO block removed:${RESET} $blk"
            info_remove_block "$blk"
            fixed=$((fixed + 1))
        fi
    done

    # 3) re-register folders that lost their registry entry
    local d bn
    while IFS= read -r d; do
        bn=$(basename "$d")
        if ! port_registry_get "$bn" >/dev/null 2>&1; then
            read -r http socks < <(instance_ports "$d")
            if [[ "$http" =~ ^[0-9]+$ && "$socks" =~ ^[0-9]+$ ]]; then
                echo -e " ${GREEN}re-registered:${RESET} $bn (HTTP:$http SOCKS:$socks)"
                port_registry_set_entry "$bn" "$http" "$socks"
                fixed=$((fixed + 1))
            else
                echo -e " ${RED}folder has no usable config:${RESET} $bn — delete it or recreate it"
            fi
        fi
    done < <(psiphon_dirs)

    # 4) reconcile pidfiles + verify ports
    while IFS= read -r d; do
        doctor_reconcile_pidfile "$d"
        read -r http socks < <(instance_ports "$d")
        for p in "$http" "$socks"; do
            [[ "$p" =~ ^[0-9]+$ ]] || continue
            if ! port_in_use "$p"; then
                # port is free while the instance claims it: either stopped
                # (fine) or crashed (worth knowing)
                if psiphon_live_pid "$d" >/dev/null 2>&1; then
                    echo -e " ${RED}process alive but port $p not listening:${RESET} $(basename "$d")"
                fi
            fi
        done
    done < <(psiphon_dirs)

    validate_info_file
    info_write_system
    generate_start_psiphon_script
    if [[ "$fixed" -eq 0 ]]; then
        echo -e "${GREEN}Doctor: everything already in sync.${RESET}"
    else
        echo -e "${GREEN}Doctor: fixed $fixed orphan(s).${RESET}"
    fi
}

# --- Health check (Phase 3) ------------------------------------------------
# health_check_socks <label> <socks-port> [proxy-user:pass]
# The shared check for every core: exit IP + latency through the SOCKS
# port + DNSBL status (zen.spamhaus.org and cb1.abuseat.org — the two
# lists IPFighter deducts for). Prints one summary line.
# Used by the Psiphon check below and by the per-core checks (Phase 4).

health_check_socks() {
    local label="$1" sp="$2" creds="${3:-}" ip ms t0
    if ! [[ "$sp" =~ ^[0-9]+$ ]]; then
        echo -e " ${RED}$label: no SOCKS port${RESET}"
        return 1
    fi
    command -v curl >/dev/null 2>&1 || { echo -e " ${RED}curl is required for health checks${RESET}"; return 1; }
    local curl_args=(-s --max-time 15 --socks5-hostname "127.0.0.1:$sp")
    [[ -n "$creds" ]] && curl_args+=(--proxy-user "$creds")
    t0=$(date +%s%N)
    ip=$(curl "${curl_args[@]}" https://ifconfig.me 2>/dev/null || true)
    ms=$(( ( $(date +%s%N) - t0 ) / 1000000 ))
    if [[ -z "$ip" ]]; then
        echo -e " ${RED}$label: SOCKS $sp answers nothing${RESET}"
        return 1
    fi
    # DNSBL: reverse the IP, query the two lists (needs dig or host)
    local bl="clean" rev ans
    if command -v dig >/dev/null 2>&1; then
        rev=$(echo "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')
        for list in zen.spamhaus.org cb1.abuseat.org; do
            ans=$(dig +short +time=5 "$rev.$list" 2>/dev/null | head -n1 || true)
            [[ -n "$ans" ]] && bl="LISTED on $list"
        done
    else
        bl="unknown (install dnsutils for DNSBL checks)"
    fi
    echo -e " ${GREEN}$label${RESET}  IP: $ip  latency: ${ms}ms  blacklist: $bl"
}

# For one instance: exit IP + latency through its SOCKS port, plus DNSBL
# status of that IP (zen.spamhaus.org and cb1.abuseat.org — the two lists
# IPFighter deducts for). Prints one summary line per instance.

health_check_instance() {
    local d="$1" sp
    read -r _hp sp < <(instance_ports "$d")
    if ! [[ "$sp" =~ ^[0-9]+$ ]]; then
        echo -e " ${RED}$(basename "$d"): no SOCKS port in config${RESET}"
        return 1
    fi
    if ! psiphon_live_pid "$d" >/dev/null 2>&1; then
        echo -e " ${RED}$(basename "$d"): not running${RESET}"
        return 1
    fi
    health_check_socks "$(basename "$d")" "$sp"
}

health_check_all() {
    echo -e "${YELLOW}Health check (exit IP + latency + blacklist):${RESET}"
    local any=0
    while IFS= read -r d; do
        any=1
        health_check_instance "$d" || true
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
}

# --- Per-core health checks (Phase 4) ---------------------------------------
# health_check_core <core-name> — WARP (1091), Tor (9050), Arman (10810).
# Same one-line format as the Psiphon check. A core whose SOCKS port is
# not listening is reported as not running, not as a failure.
# Arman note: its SOCKS port needs the username/password generated at
# setup (stored in its config.json — the exact key is unverified), so
# without them the check can only report whether the port is up, not
# the exit IP. That is reported honestly instead of a fake "no answer".

health_check_core() {
    local name="$1" sp=""
    case "$name" in
        warp)  sp=1091 ;;
        tor)   sp=9050 ;;
        arman) sp=10810 ;;
        *) echo -e "${RED}Unknown core for health check: $name${RESET}"; return 1 ;;
    esac
    if ! port_in_use "$sp"; then
        echo -e " ${YELLOW}$name: not running (nothing on SOCKS $sp)${RESET}"
        return 1
    fi
    if [[ "$name" == "arman" ]]; then
        echo -e " ${GREEN}arman${RESET}  SOCKS 10810 is listening — full exit-IP check needs the setup username/password (config.json key unverified, see docs/PHASES.md Phase 4)"
        return 0
    fi
    health_check_socks "$name" "$sp"
}

health_check_cores_all() {
    echo -e "${YELLOW}Core health check (exit IP + latency + blacklist):${RESET}"
    local name
    for name in warp tor arman; do
        health_check_core "$name" || true
    done
}
