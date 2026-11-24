#!/bin/bash
# multifon v2 — lib/doctor.sh
# Doctor / sync + health checks.
# Fixes bugs #5 and #6: state is reconciled from the LIVE process and the
# real folders on disk, not from registry files alone. (v2.3: the pidfile
# is gone — systemd tracks each instance's process, so the pidfile-desync
# bug class is dead at the root; doctor now reconciles UNITS instead.)
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_DOCTOR_LOADED:-}" ]] && return 0
_MULTIFON_DOCTOR_LOADED=1

# Print the PID of the live Psiphon process for one instance folder.
# 1) the unit's MainPID (systemd tracks the process — the authoritative
#    answer when the unit is active).
# 2) the tunnel core itself (its cwd is the instance folder) — covers a
#    manually started process with no unit.
# Prints nothing + returns 1 when the instance is not running.
psiphon_live_pid() {
    local d="$1" pid="" cwd=""
    if command -v systemctl >/dev/null 2>&1; then
        pid=$(systemctl show -p MainPID --value "$(systemd_unit_name "$d")" 2>/dev/null || true)
        if [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    command -v pgrep >/dev/null 2>&1 || return 1
    for pid in $(pgrep -f "psiphon-tunnel-core" 2>/dev/null || true); do
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
        if [[ "$cwd" == "$d" ]]; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# Reconcile ONE folder's unit with reality (v2.3 — replaces the old
# systemd tracks the process, but the unit itself can still be missing
# or stale):
#  - stale v2.2 start.sh lying around -> remove it
#  - folder exists but the unit is not active  -> (re)create the unit;
#    if the core is already running outside systemd, stop it first and
#    start the unit instead, so exactly one process owns the ports
doctor_reconcile_unit() {
    local d="$1" live=""
    if [ -f "$d/start.sh" ]; then
        echo -e " ${YELLOW}stale v2.2 start.sh removed:${RESET} $(basename "$d")"
        rm -f "$d/start.sh"
    fi
    live=$(psiphon_live_pid "$d" || true)
    if ! systemd_unit_is_active "$(systemd_unit_name "$d")" 2>/dev/null; then
        systemd_unit_ensure "$d" || return 1
        if [[ -n "$live" ]]; then
            echo -e " ${YELLOW}core was running outside systemd — stopping it and starting the unit:${RESET} $(basename "$d")"
            _kill_pid "$live" 2>/dev/null || true
            systemd_instance_start "$d"
        else
            echo -e " ${GREEN}unit (re)created:${RESET} $(basename "$d") (stopped)"
        fi
    fi
}

# doctor_sync — the canonical repair pass (bugs #1/#5/#6).
#  - registry entries whose folder is gone     -> prune entry + INFO block
#  - INFO blocks whose folder is gone          -> prune block
#  - folders with no registry entry            -> re-register from config.json
#  - missing / stale units                     -> reconcile from live process
#  - ports the registry claims but nobody holds -> report as free again
doctor_sync() {
    echo -e "${YELLOW}Doctor: syncing registry + INFO + folders + units...${RESET}"
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

    # 3.5) repair broken instance binaries (v2.3.1): a wrapper / non-ELF /
    # too-small binary (the SpherionOS /usr/bin/psiphon case) is replaced
    # with the verified official core from /usr/bin/psiphon-tunnel-core-x86_64.
    # Runs BEFORE the unit reconcile, or unit creation would refuse the
    # bad binary. Counts as a fix when it repairs anything.
    local repair_out repair_rc repaired=0
    repair_out=$(repair_instance_binaries 2>&1); repair_rc=$?
    echo "$repair_out"
    if [[ "$repair_rc" -eq 0 ]]; then
        repaired=$(echo "$repair_out" | tail -n1 | grep -oE '[0-9]+' | head -n1)
        [[ "$repaired" =~ ^[0-9]+$ ]] && fixed=$((fixed + repaired))
    fi

    # 4) reconcile units + verify ports
    local issues=0
    while IFS= read -r d; do
        doctor_reconcile_unit "$d"
        if ! systemd_unit_is_active "$(systemd_unit_name "$d")" 2>/dev/null; then
            echo -e " ${YELLOW}unit not running:${RESET} $(basename "$d") ($(systemd_unit_state "$(systemd_unit_name "$d")")) — start it from menu 3 -> 3 (doctor never starts a stopped instance on its own)"
            issues=$((issues + 1))
        fi
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

    # 5) legacy firewall rules (uid-owner / server-wide) still present?
    if firewall_legacy_rules_present 2>/dev/null; then
        echo -e " ${YELLOW}legacy firewall rules present (uid-owner/server-wide) — re-enable the scoped block once (menu 8 -> 2) to migrate${RESET}"
        issues=$((issues + 1))
    fi

    # 5.5) scoped block gone or below the UFW jumps (v2.3.3)? Rules live
    # only in the running firewall: a reboot or `ufw reload` wipes
    # OUTPUT, and v2.3.1 APPENDED the rules below the UFW jumps, where
    # they are never evaluated (all counters 0). If the oneshot unit
    # says the block should be on but the rules are gone — or they sit
    # below UFW — delete + re-insert them at the top of OUTPUT now.
    if [[ -f "$SYSTEMD_UNIT_DIR/$FIREWALL_ONESHOT_UNIT" ]] && [[ "$(dns_leak_block_status 2>/dev/null)" == "open" ]]; then
        echo -e " ${YELLOW}scoped block was enabled but its rules are gone (reboot / ufw reload?) — re-applying at the top of OUTPUT...${RESET}"
        dns_leak_block_reapply 2>/dev/null || true
        fixed=$((fixed + 1))
    elif _scoped_block_below_ufw 2>/dev/null; then
        echo -e " ${YELLOW}scoped block rules sit below the UFW jumps (never evaluated) — moving them to the top of OUTPUT...${RESET}"
        dns_leak_block_reapply 2>/dev/null || true
        fixed=$((fixed + 1))
    fi

    validate_info_file
    info_write_system
    systemd_units_sync 2>/dev/null || true
    # v2.3.1: "everything already in sync" is only true when nothing was
    # fixed AND no unit is stopped AND no legacy rules remain. Stopped
    # units are reported, not hidden — that is how the 90-byte binary hid.
    if [[ "$fixed" -eq 0 && "$issues" -eq 0 ]]; then
        echo -e "${GREEN}Doctor: everything already in sync.${RESET}"
    else
        [[ "$fixed" -gt 0 ]] && echo -e "${GREEN}Doctor: fixed $fixed orphan(s).${RESET}"
        [[ "$issues" -gt 0 ]] && echo -e "${YELLOW}Doctor: $issues issue(s) above still need action.${RESET}"
    fi
}

# --- Health check (Phase 3) ------------------------------------------------
# health_check_socks <label> <socks-port> [proxy-user:pass]
# The shared check for every core: exit IP + latency through the SOCKS
# port + DNSBL status (zen.spamhaus.org and cb1.abuseat.org — the two
# lists IPFighter deducts for). Prints one summary line.
# Used by the Psiphon check below and by the per-core checks (Phase 4).
# Latency (v2.3.3 — single back-to-back samples lie: 1-CPU box, 3
# instances contend, Psiphon exits rotate and their load varies between
# samples; the user measured 300ms then 600-700ms for the same egresses):
# N=3 samples to Google's generate_204 endpoint (light, same Google edge
# infra as Gemini — the service he actually uses), ~2s apart, NEVER in
# parallel. Reports the MEDIAN + jitter (max-min across samples), not
# one number. The exit IP still comes from one ifconfig.me fetch.
# Results are appended to $HC_COLLECT (if set) as "label|median|jitter"
# for ranking by health_check_all; unknown jitter records as 999999
# (ranks last), a missing median as 999999 too.
health_check_socks() {
    local label="$1" sp="$2" creds="${3:-}" ip
    if ! [[ "$sp" =~ ^[0-9]+$ ]]; then
        echo -e " ${RED}$label: no SOCKS port${RESET}"
        return 1
    fi
    command -v curl >/dev/null 2>&1 || { echo -e " ${RED}curl is required for health checks${RESET}"; return 1; }
    local curl_args=(-s --max-time 15 --socks5-hostname "127.0.0.1:$sp")
    [[ -n "$creds" ]] && curl_args+=(--proxy-user "$creds")
    ip=$(curl "${curl_args[@]}" https://ifconfig.me 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
        echo -e " ${RED}$label: SOCKS $sp answers nothing${RESET}"
        return 1
    fi
    # Latency: 3 spaced samples to Google, median + jitter.
    local samples=() i t ms
    for i in 1 2 3; do
        [[ "$i" -gt 1 ]] && sleep 2
        t=$(curl -s -o /dev/null -w '%{time_total}' --max-time 15 --socks5-hostname "127.0.0.1:$sp" ${creds:+--proxy-user "$creds"} https://www.google.com/generate_204 2>/dev/null || true)
        ms=$(awk -v v="$t" 'BEGIN { if (v ~ /^[0-9.]+$/) printf "%d", v*1000; else print "" }')
        [[ -n "$ms" ]] && samples+=("$ms")
    done
    local lat_text median="999999" jitter="999999"
    if [[ "${#samples[@]}" -ge 2 ]]; then
        median=$(printf '%s\n' "${samples[@]}" | sort -n | awk '{a[NR]=$1} END {n=NR; if (n%2) print a[(n+1)/2]; else print int((a[n/2]+a[n/2+1])/2)}')
        jitter=$(printf '%s\n' "${samples[@]}" | sort -n | awk 'NR==1{min=$1} {max=$1} END {print max-min}')
        lat_text="latency: ${median}ms median (jitter ${jitter}ms; samples $(IFS=/; echo "${samples[*]}")ms)"
    elif [[ "${#samples[@]}" -eq 1 ]]; then
        median="${samples[0]}"
        lat_text="latency: ${samples[0]}ms (only 1/3 samples answered — jitter unknown)"
    else
        lat_text="latency: n/a (Google did not answer through this egress)"
    fi
    [[ -n "${HC_COLLECT:-}" ]] && echo "$label|$median|$jitter" >> "$HC_COLLECT"
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
    echo -e " ${GREEN}$label${RESET}  IP: $ip  $lat_text  blacklist: $bl"
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
    echo -e "${YELLOW}Health check (exit IP + median latency + jitter + blacklist):${RESET}"
    echo -e "${CYAN}Latency: 3 samples per egress, ~2s apart, to Google (generate_204) — median + jitter, never back-to-back, never parallel.${RESET}"
    local any=0 first=1
    HC_COLLECT=$(mktemp)
    while IFS= read -r d; do
        any=1
        # Short pause between egresses: measuring them back-to-back on
        # this 1-CPU box contends and skews the numbers.
        [[ "$first" -eq 0 ]] && sleep 1
        first=0
        health_check_instance "$d" || true
    done < <(psiphon_dirs)
    if [[ "$any" -eq 0 ]]; then
        echo -e "${RED}No psiphon-* locations found.${RESET}"
        rm -f "$HC_COLLECT"; unset HC_COLLECT
        return 0
    fi
    # Rank by median, then jitter; say which egress is best right now.
    if [[ -s "$HC_COLLECT" ]]; then
        local best blabel bmed bjit
        best=$(sort -t'|' -k2,2n -k3,3n "$HC_COLLECT" | head -n1)
        IFS='|' read -r blabel bmed bjit <<< "$best"
        if [[ "$bmed" != "999999" ]]; then
            echo -e " ${GREEN}Best now: $blabel (median ${bmed}ms, jitter ${bjit}ms)${RESET}"
        fi
        echo -e " ${CYAN}Ranking (median, then jitter):${RESET}"
        sort -t'|' -k2,2n -k3,3n "$HC_COLLECT" | while IFS='|' read -r l m j; do
            if [[ "$m" == "999999" ]]; then
                echo -e "   $l — no usable latency samples"
            elif [[ "$j" == "999999" ]]; then
                echo -e "   $l — median ${m}ms, jitter unknown (1 sample)"
            else
                echo -e "   $l — median ${m}ms, jitter ${j}ms"
            fi
        done
    fi
    rm -f "$HC_COLLECT"; unset HC_COLLECT
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

# --- Clean slate / factory reset (v2.3.1) ----------------------------------
# multifon_nuke — delete EVERYTHING multifon created and leave the machine
# ready for a fresh rebuild with the fixed script. This is the SINGLE
# place where "things that get cleaned" live (the old one-off sandbox
# removal entry is gone — its package purge moved in here).
#   Deletes: all instance dirs + registry/INFO/markers/DoH configs under
#     $PSIPHON_BASE_DIR/psiphon, all multifon-psiphon-*.service units
#     (+ the dead oneshot autostart unit), all multifon-<cc> users (and
#     the old bare `multifon` user, if it still exists) + the multifon
#     group, the scoped gid-owner AND legacy uid-owner / server-wide
#     firewall rules (+ per-instance INPUT rules), the DoH forwarders,
#     the /usr/bin/psiphon wrapper, /etc/psiphon leftovers, and the old
#     sandbox package + its ~1 GB autoremove set.
#   KEEPS: the verified real core /usr/bin/psiphon-tunnel-core-x86_64
#     (the fixed create path reuses it after verification).
#   NEVER deletes: the ~/multifon checkout itself — the running script
#     would delete itself mid-run. That stays a manual last step (see
#     the message this prints at the end).
# Prints exactly what it will delete and asks confirm_yes first — never
# silent. Run it ONLY after the v2.3.1 merge is pulled: the rebuild
# needs the fixed create path.
multifon_nuke() {
    local data_dir="$PSIPHON_BASE_DIR/psiphon"
    echo -e "${RED}${BOLD}CLEAN SLATE — this deletes everything multifon created:${RESET}"
    echo ""
    echo "  Instances + data:  $data_dir  (all psiphon-<cc> dirs, .allocated_ports,"
    echo "                     INFO.txt, .sandbox-gid, .dns, .core-sha256)"
    echo "  Units:             all multifon-psiphon-*.service (+ old oneshot autostart unit)"
    echo "                     (+ the firewall oneshot multifon-firewall.service, if installed)"
    echo "  Users + group:     multifon-<cc> users (+ old bare multifon user), group multifon"
    echo "  Firewall:          scoped gid-owner + legacy uid-owner/server-wide rules"
    echo "                     (+ per-instance INPUT rules)"
    echo "  DoH forwarders:    all dnscrypt-proxy forwarders (stop + remove configs)"
    echo "  Binaries:          /usr/bin/psiphon (broken wrapper), /etc/psiphon leftovers"
    echo "  Old sandbox pkg:   purge + apt autoremove --purge (~1 GB)"
    echo ""
    echo -e "${GREEN}KEPT: /usr/bin/psiphon-tunnel-core-x86_64 (verified real core)${RESET}"
    echo -e "${GREEN}NOT deleted here: ~/multifon (the checkout — manual last step, see below)${RESET}"
    echo ""
    echo -e "${YELLOW}Disk before:${RESET}"
    df -h / | tail -n1
    echo ""
    if ! confirm_yes "Delete ALL of the above and start from a clean slate?"; then
        echo -e "${YELLOW}Aborted — nothing was deleted.${RESET}"
        return 1
    fi

    # 1) Stop the DoH forwarders (they belong to the deleted instances),
    #    then stop every instance unit.
    echo -e "${CYAN}[1/8] Stopping DoH forwarders...${RESET}"
    dns_forwarder_stop_all 2>/dev/null || true
    echo -e "${CYAN}[2/8] Stopping all instance units...${RESET}"
    systemd_stop_all 2>/dev/null || true
    # Any core process still alive (e.g. started outside its unit).
    local pid
    for pid in $(pgrep -f "psiphon-tunnel-core" 2>/dev/null || true); do
        echo -e "${YELLOW}Killing leftover core process $pid...${RESET}"
        _kill_pid "$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done

    # 2) Disable + remove the unit files (+ the dead oneshot autostart).
    echo -e "${CYAN}[3/8] Removing unit files...${RESET}"
    local unit
    shopt -s nullglob
    for unit in "$SYSTEMD_UNIT_DIR"/multifon-psiphon-*.service; do
        sudo systemctl disable --now "$(basename "$unit")" >/dev/null 2>&1 || true
        sudo rm -f "$unit"
        echo "  removed $(basename "$unit")"
    done
    shopt -u nullglob
    if [[ -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT" ]]; then
        sudo systemctl disable --now "$LEGACY_AUTOSTART_UNIT" >/dev/null 2>&1 || true
        sudo rm -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT"
        echo "  removed $LEGACY_AUTOSTART_UNIT"
    fi
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl reset-failed 2>/dev/null || true

    # 3) Firewall: scoped + legacy rules, then per-instance INPUT rules.
    echo -e "${CYAN}[4/8] Removing firewall rules...${RESET}"
    dns_leak_block_disable 2>/dev/null || true
    local d
    while IFS= read -r d; do
        firewall_close_instance_ports "$(basename "$d")" 2>/dev/null || true
    done < <(psiphon_dirs)

    # 4) Delete the per-instance users + the shared group.
    echo -e "${CYAN}[5/8] Deleting users + group...${RESET}"
    local u
    while IFS= read -r d; do
        u=$(systemd_instance_user "$d")
        if id -u "$u" >/dev/null 2>&1; then
            if sudo userdel "$u" 2>/dev/null || userdel "$u" 2>/dev/null; then
                echo "  deleted user $u"
            else
                echo -e "  ${YELLOW}could not delete user $u (still has processes?) — check: id $u${RESET}"
            fi
        fi
    done < <(psiphon_dirs)
    # Users whose folder is already gone (incl. the old bare `multifon` user).
    while IFS=: read -r u _; do
        [[ "$u" == "multifon" || "$u" == multifon-* ]] || continue
        if sudo userdel "$u" 2>/dev/null || userdel "$u" 2>/dev/null; then
            echo "  deleted user $u"
        fi
    done < <(getent passwd)
    if getent group "$SANDBOX_GROUP" >/dev/null 2>&1; then
        if sudo groupdel "$SANDBOX_GROUP" 2>/dev/null || groupdel "$SANDBOX_GROUP" 2>/dev/null; then
            echo "  deleted group $SANDBOX_GROUP"
        else
            echo -e "  ${YELLOW}could not delete group $SANDBOX_GROUP — check: getent group $SANDBOX_GROUP${RESET}"
        fi
    fi

    # 5) Delete the data dir (instances, registry, INFO, markers, DoH).
    echo -e "${CYAN}[6/8] Deleting $data_dir ...${RESET}"
    if [[ -d "$data_dir" ]]; then
        sudo rm -rf "$data_dir" 2>/dev/null || rm -rf "$data_dir" 2>/dev/null || true
        if [[ -d "$data_dir" ]]; then
            echo -e "  ${RED}could not delete $data_dir — check permissions and remove it by hand.${RESET}"
        else
            echo "  removed $data_dir"
        fi
    fi

    # 6) Wrapper + /etc leftovers. The verified core is KEPT.
    echo -e "${CYAN}[7/8] Removing the broken wrapper + /etc leftovers...${RESET}"
    sudo rm -f /usr/bin/psiphon 2>/dev/null || rm -f /usr/bin/psiphon 2>/dev/null || true
    [[ -e /usr/bin/psiphon ]] || echo "  removed /usr/bin/psiphon"
    sudo rm -rf /etc/psiphon 2>/dev/null || rm -rf /etc/psiphon 2>/dev/null || true
    [[ -e /etc/psiphon ]] || echo "  removed /etc/psiphon"
    if _core_file_ok_quiet "/usr/bin/psiphon-tunnel-core-x86_64"; then
        echo -e "  ${GREEN}kept verified core /usr/bin/psiphon-tunnel-core-x86_64 ($(stat -c%s /usr/bin/psiphon-tunnel-core-x86_64 2>/dev/null || echo ?) bytes)${RESET}"
    else
        echo -e "  ${RED}WARNING: no verified core at /usr/bin/psiphon-tunnel-core-x86_64 — run menu 10 -> 1 to download it before recreating.${RESET}"
    fi

    # 7) Old sandbox package purge + autoremove (dry-run first).
    echo -e "${CYAN}[8/8] Purging the old sandbox package...${RESET}"
    if command -v firejail >/dev/null 2>&1 || dpkg -l firejail 2>/dev/null | grep -q '^ii'; then
        sudo apt purge -y firejail firejail-profiles || echo -e "${YELLOW}apt purge had an issue — continuing anyway.${RESET}"
    else
        echo -e "${GREEN}Old sandbox package is already gone.${RESET}"
    fi
    echo ""
    echo -e "${YELLOW}These packages would be autoremoved:${RESET}"
    sudo apt autoremove --dry-run 2>/dev/null | sed -n '/will be REMOVED/,/^$/p' | head -n 20
    echo ""
    sudo apt autoremove --purge -y || echo -e "${YELLOW}autoremove had an issue — check apt output above.${RESET}"

    echo ""
    echo -e "${YELLOW}Disk after:${RESET}"
    df -h / | tail -n1
    echo ""
    echo -e "${GREEN}Clean slate done. Nothing multifon-owned is left except the verified core.${RESET}"
    echo ""
    echo -e "${CYAN}Rebuild (with the fixed script):${RESET}"
    echo "  1) Menu 3 -> create the instances (NL/SE/SG as before, or the"
    echo "     recommended DE/NL/SE/SG — your choice, not hardcoded), then"
    echo "     menu 3 -> 3 (start-all)."
    echo "  2) Manual last step — the checkout itself: only after you have"
    echo "     confirmed 'multifon' works from another directory (menu 9),"
    echo "     remove the old checkout and re-clone fresh:"
    echo "       rm -rf ~/multifon"
}
