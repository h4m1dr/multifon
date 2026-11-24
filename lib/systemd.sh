#!/bin/bash
# multifon v2.3 — lib/systemd.sh
# systemd sandbox: one unit per Psiphon instance. REPLACES Firejail.
#
# Why Firejail is gone: `apt install firejail` pulled ~1 GB of Recommends
# (xpra + the GTK/GL dev stack) for a 1.6 MB sandbox, and Firejail is a
# setuid-root binary with a long CVE history. What Firejail actually did
# for multifon was three things, and systemd does all three natively:
#   1) per-instance private filesystem — Firejail --private=<dir> gave
#      each instance its own state dir, so Psiphon counted them as
#      separate clients and gave separate exit IPs (shared data dir =
#      one client = one exit IP; that is why Firejail was installed).
#      systemd replaces the mount namespace with Unix permissions:
#      each instance runs as its own system user (multifon-<cc>) and
#      its folder is mode 700 owned by that user, so instances cannot
#      see each other's folders at all.
#   2) a uid to scope the firewall to — the v2.1 scoped port-53 + STUN
#      block used iptables owner-match on the single `multifon` uid.
#      Now all instance users share the group `multifon`, and the rules
#      match --gid-owner multifon (one rule set, see lib/firewall.sh).
#   3) per-egress timezone — the unit sets Environment=TZ=<zone> (+ a
#      BindPaths of the zoneinfo file). Same honest limit as before:
#      this changes the psiphon process timezone only, NOT the browser
#      timezone IPFighter reads.
#
# What systemd ALSO fixes: process tracking. The old launchers recorded
# a pidfile (psiphon.firejail.pid) that went stale whenever an instance
# was stopped by hand — the pidfile-desync bug class (#5). A unit is
# tracked by systemd itself: start/stop/restart/status/is-active, logs
# in the journal + log.txt, Restart=on-failure. No pidfiles anywhere.
#
# BASE DIR / TRAVERSAL — read this before wondering why a unit cannot
# start: instances live under $PSIPHON_BASE_DIR/psiphon/ (v1: $HOME,
# so /root/psiphon/ when run as root). /root is mode 700, so an
# instance user could not even traverse into its own folder.
# systemd_ensure_traversal() fixes exactly that and nothing more:
# it chgrp's $PSIPHON_BASE_DIR and $PSIPHON_BASE_DIR/psiphon to the
# `multifon` group and adds group-execute (g+x) — traverse a known
# path, NOT list the directory (no read bit is added). Exposure, stated
# honestly: an instance user can reach world-readable files under those
# two directories BY EXACT NAME (e.g. INFO.txt, .allocated_ports —
# ports and paths, no secrets). Real secrets in $HOME (gdrive-sa.json,
# encrypt_key.txt, ...) should be chmod 600 — good hygiene anyway, and
# then they are unreadable to the instance users despite traversal.
# ProtectSystem=strict + ReadWritePaths=<instance dir> confines WRITES
# to the instance folder; ProtectHome is deliberately NOT set, because
# the instance dir lives under /root and ProtectHome would fight the
# ReadWritePaths carve-out. NoNewPrivileges + PrivateTmp + UMask=0077
# are on. CapabilityBoundingSet / SystemCallFilter are intentionally
# NOT set: the core is a trusted official binary, and a wrong filter
# would break the tunnel with no benefit.
#
# The old oneshot autostart service (multifon-psiphon.service, which
# ran start-psiphons.sh) is dead in v2.3 — per-instance units replace
# it, and systemd_units_sync / systemd_remove_firejail remove it.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_SYSTEMD_LOADED:-}" ]] && return 0
_MULTIFON_SYSTEMD_LOADED=1

# Shared group for every instance user; the firewall matches it.
SANDBOX_GROUP="multifon"
# Marker written by the one-time group setup (records the gid).
SANDBOX_GID_FILE="$PSIPHON_BASE_DIR/psiphon/.sandbox-gid"
# Legacy v2.1 marker (single `multifon` uid) — removed on setup, never created.
SANDBOX_UID_FILE_LEGACY="$PSIPHON_BASE_DIR/psiphon/.sandbox-uid"
SYSTEMD_UNIT_DIR="/etc/systemd/system"
# Legacy oneshot autostart service (v1–v2.2, ran start-psiphons.sh).
LEGACY_AUTOSTART_UNIT="multifon-psiphon.service"

# --- Naming ---------------------------------------------------------------
# systemd_unit_name <dir> -> multifon-psiphon-cz.service
systemd_unit_name() {
    printf 'multifon-%s.service' "$(basename "$1")"
}

# systemd_instance_cc <dir> -> cz (lowercase, from the folder name)
systemd_instance_cc() {
    local bn
    bn="$(basename "$1")"
    printf '%s' "${bn#psiphon-}"
}

# systemd_instance_user <dir> -> multifon-cz
systemd_instance_user() {
    printf 'multifon-%s' "$(systemd_instance_cc "$1")"
}

# systemd_first_instance_user — the user of the first instance folder,
# but only if that user exists (used for the DNS leak probe). Prints
# nothing when there are no instances or the user is not set up yet.
systemd_first_instance_user() {
    local d u
    d=$(psiphon_dirs 2>/dev/null | head -n1 || true)
    [[ -n "$d" ]] || return 1
    u=$(systemd_instance_user "$d")
    id -u "$u" >/dev/null 2>&1 || return 1
    printf '%s' "$u"
}

# --- Group + users ---------------------------------------------------------
# systemd_group_ensure — create the shared `multifon` group if missing.
# Prints the gid.
systemd_group_ensure() {
    local gid
    gid=$(getent group "$SANDBOX_GROUP" | cut -d: -f3 || true)
    if [[ -z "$gid" ]]; then
        echo -e "${CYAN}Creating system group '$SANDBOX_GROUP' for the instance users...${RESET}"
        sudo groupadd --system "$SANDBOX_GROUP" \
            || { echo -e "${RED}Could not create group $SANDBOX_GROUP.${RESET}"; return 1; }
        gid=$(getent group "$SANDBOX_GROUP" | cut -d: -f3 || true)
        [[ -n "$gid" ]] || { echo -e "${RED}Group $SANDBOX_GROUP still missing after groupadd.${RESET}"; return 1; }
    fi
    echo "$gid"
}

# True when the sandbox group is set up (marker file + group exists).
sandbox_group_enabled() {
    [[ -f "$SANDBOX_GID_FILE" ]] && getent group "$SANDBOX_GROUP" >/dev/null 2>&1
}

# systemd_ensure_traversal — let the instance users reach their folders.
# chgrp + g+x on the base dir and the psiphon dir only (see the header
# note for the exact exposure). Never touches anything else.
systemd_ensure_traversal() {
    local base="$PSIPHON_BASE_DIR" root="$PSIPHON_BASE_DIR/psiphon"
    mkdir -p "$root"
    sudo chgrp "$SANDBOX_GROUP" "$base" "$root" 2>/dev/null || true
    sudo chmod g+x "$base" "$root" 2>/dev/null || true
}

# systemd_user_ensure <dir> — create the per-instance system user if
# missing, then hand the folder to it (700, owned user:multifon).
# Prints the username.
systemd_user_ensure() {
    local d="$1" cc user
    cc=$(systemd_instance_cc "$d")
    user="multifon-$cc"
    systemd_group_ensure >/dev/null || return 1
    if ! id -u "$user" >/dev/null 2>&1; then
        echo -e "${CYAN}Creating system user '$user' for $(basename "$d")...${RESET}"
        sudo useradd --system --no-create-home --home-dir "$d" \
            --shell /usr/sbin/nologin -g "$SANDBOX_GROUP" "$user" \
            || { echo -e "${RED}Could not create user $user.${RESET}"; return 1; }
    fi
    systemd_ensure_traversal
    sudo chown -R "$user:$SANDBOX_GROUP" "$d" \
        || { echo -e "${RED}chown failed for $d.${RESET}"; return 1; }
    sudo chmod 700 "$d"
    echo "$user"
}

# --- Units -----------------------------------------------------------------
# systemd_unit_write <dir> — write (or rewrite) the unit for one instance.
# The zone comes from egress_timezone() (lib/psiphon.sh); the unit is
# enabled afterwards. Does NOT start the unit — callers decide that.
# Returns 1 when the instance binary is missing.
systemd_unit_write() {
    local d="$1" bn cc user tz zi unit tmp bin
    bn="$(basename "$d")"
    cc="${bn#psiphon-}"; cc="${cc^^}"
    user=$(systemd_instance_user "$d")
    tz=$(egress_timezone "$cc")
    unit="$SYSTEMD_UNIT_DIR/$(systemd_unit_name "$d")"

    # The binary must be the x86_64 one; keep the v1 rename fallback.
    # v2.3.1: -x alone is not enough — a 90-byte wrapper script is also
    # +x, and it exits 127 in the unit forever. Verify ELF + size.
    bin="$d/psiphon-tunnel-core-x86_64"
    if [[ ! -x "$bin" ]]; then
        if [[ -f "$d/psiphon-tunnel-core" ]]; then
            mv "$d/psiphon-tunnel-core" "$bin"
            chmod +x "$bin"
        else
            echo -e "${RED}No Psiphon binary in $d — cannot write its unit.${RESET}"
            return 1
        fi
    fi
    if ! psiphon_verify_instance_binary "$bin"; then
        echo -e "${RED}Bad binary in $d — not a real core (see above). Delete the instance and recreate it after getting a real binary (menu 10 -> 1).${RESET}"
        return 1
    fi

    tmp=$(mktemp) || return 1
    {
        printf '%s\n' "[Unit]"
        printf 'Description=multifon Psiphon instance %s (egress %s)\n' "$bn" "$cc"
        printf '%s\n' "After=network-online.target"
        printf '%s\n' "Wants=network-online.target"
        # Restart-loop protection (v2.3.1): Restart=on-failure +
        # RestartSec=5 alone restarts forever — the default burst limit
        # (5 restarts in 10s) is never hit because restarts are 5s apart
        # (a broken 90-byte binary hit restart #102 in ~8 min). 5 failures
        # in 5 min -> the unit goes failed and STOPS, instead of looping.
        printf '%s\n' "StartLimitIntervalSec=300"
        printf '%s\n' "StartLimitBurst=5"
        printf '%s\n' ""
        printf '%s\n' "[Service]"
        printf '%s\n' "Type=simple"
        printf 'User=%s\n' "$user"
        printf 'Group=%s\n' "$SANDBOX_GROUP"
        printf 'WorkingDirectory=%s\n' "$d"
        printf 'ExecStart=%s -config ./config.json\n' "$bin"
        if [[ "$tz" != "UTC" ]]; then
            printf 'Environment=TZ=%s\n' "$tz"
            zi="/usr/share/zoneinfo/$tz"
            if [[ -f "$zi" ]]; then
                printf 'BindPaths=%s:/etc/localtime\n' "$zi"
            fi
        fi
        printf '%s\n' "ProtectSystem=strict"
        printf 'ReadWritePaths=%s\n' "$d"
        printf '%s\n' "PrivateTmp=yes"
        printf '%s\n' "NoNewPrivileges=yes"
        printf '%s\n' "UMask=0077"
        printf '%s\n' "Restart=on-failure"
        printf '%s\n' "RestartSec=5"
        printf 'StandardOutput=append:%s/log.txt\n' "$d"
        printf 'StandardError=append:%s/log.txt\n' "$d"
        printf '%s\n' ""
        printf '%s\n' "[Install]"
        printf '%s\n' "WantedBy=multi-user.target"
    } > "$tmp"
    sudo install -m 0644 "$tmp" "$unit"
    rm -f "$tmp"
    sudo systemctl daemon-reload
    sudo systemctl enable "$(systemd_unit_name "$d")" >/dev/null 2>&1 || true
    echo "$unit"
}

# systemd_unit_ensure <dir> — user + unit, no start. Idempotent.
# Used by doctor/sync and by creation (which then starts the unit).
systemd_unit_ensure() {
    local d="$1"
    systemd_user_ensure "$d" >/dev/null || return 1
    systemd_unit_write "$d" >/dev/null || return 1
    return 0
}

# systemd_instance_apply <dir> <CC> — ensure user + unit, then start it.
# The creation path: a new instance starts right away, like v2.2 did
# through the oneshot service.
systemd_instance_apply() {
    local d="$1"
    systemd_unit_ensure "$d" || return 1
    systemd_instance_start "$d"
}

# --- Lifecycle (systemctl) --------------------------------------------------
# systemd_unit_is_active <unit> — quiet boolean.
systemd_unit_is_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# systemd_instance_preflight <dir> — refuse to start an instance whose
# binary is not a real core or whose config is missing/broken. A start
# that would exit 127 (or crash on a bad config) is reported HERE,
# instead of letting the unit fail and restart forever.
systemd_instance_preflight() {
    local d="$1" bin
    bin="$d/psiphon-tunnel-core-x86_64"
    if [[ ! -f "$bin" ]]; then
        echo -e "${RED}$(basename "$d"): no binary in $d — cannot start. Delete and recreate it (menu 3 -> 1) after getting a real core (menu 10 -> 1).${RESET}"
        return 1
    fi
    if ! psiphon_verify_instance_binary "$bin"; then
        echo -e "${RED}$(basename "$d"): bad binary in $d — not a real core (see above). Delete the instance and recreate it after getting a real binary (menu 10 -> 1).${RESET}"
        return 1
    fi
    if [[ ! -f "$d/config.json" ]]; then
        echo -e "${RED}$(basename "$d"): config.json is missing in $d — cannot start.${RESET}"
        return 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$d/config.json" 2>/dev/null; then
            echo -e "${RED}$(basename "$d"): config.json does not parse as JSON — cannot start.${RESET}"
            return 1
        fi
    elif command -v jq >/dev/null 2>&1; then
        if ! jq -e . "$d/config.json" >/dev/null 2>&1; then
            echo -e "${RED}$(basename "$d"): config.json does not parse as JSON — cannot start.${RESET}"
            return 1
        fi
    fi
    return 0
}

# systemd_unit_state <unit> — RUNNING / FAILED (<result>) /
# RESTART-LOOP (restart #N) / STARTING / STOPPED / NO UNIT.
# is-active alone cannot tell a failed unit from a stopped one, and a
# unit in "activating (auto-restart)" is NOT stopped — it is looping.
systemd_unit_state() {
    local unit="$1" active sub result restarts load
    load=$(systemctl show -p LoadState --value "$unit" 2>/dev/null || echo unknown)
    [[ "$load" == "loaded" ]] || { echo "NO UNIT"; return 0; }
    active=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo unknown)
    sub=$(systemctl show -p SubState --value "$unit" 2>/dev/null || true)
    result=$(systemctl show -p Result --value "$unit" 2>/dev/null || true)
    restarts=$(systemctl show -p NRestarts --value "$unit" 2>/dev/null || echo 0)
    case "$active" in
        active) echo "RUNNING" ;;
        failed) echo "FAILED${result:+ ($result)}" ;;
        activating)
            if [[ "$sub" == "auto-restart" ]]; then
                echo "RESTART-LOOP (restart #${restarts:-?})"
            else
                echo "STARTING"
            fi
            ;;
        *) echo "STOPPED" ;;
    esac
}

# systemd_instance_start <dir> — start the unit (restart if already active,
# so a "launch" always gives a fresh process — the rotate_ip semantics).
# v2.3.1: the systemctl error is PRINTED (the old code swallowed stderr,
# so a failed start looked identical to a successful one), and the unit
# is verified to have stayed up afterwards — `systemctl start` reports
# success as soon as the process forks, even if it exits immediately.
systemd_instance_start() {
    local d="$1" unit out
    unit=$(systemd_unit_name "$d")
    systemd_instance_preflight "$d" || return 1
    if systemd_unit_is_active "$unit"; then
        out=$(sudo systemctl restart "$unit" 2>&1 || systemctl restart "$unit" 2>&1) || { echo -e "${RED}Could not restart $(basename "$d") ($unit):${RESET}"; echo "$out" | tail -n 5; return 1; }
    else
        out=$(sudo systemctl start "$unit" 2>&1 || systemctl start "$unit" 2>&1) || { echo -e "${RED}Could not start $(basename "$d") ($unit):${RESET}"; echo "$out" | tail -n 5; return 1; }
    fi
    sleep 1
    if ! systemd_unit_is_active "$unit"; then
        echo -e "${RED}$(basename "$d") did not stay up ($unit): state $(systemd_unit_state "$unit") — check: systemctl status $unit; journalctl -u $unit -n 30${RESET}"
        return 1
    fi
}

# systemd_instance_stop <dir> — stop the unit (no-op when not active).
systemd_instance_stop() {
    local d="$1" unit
    unit=$(systemd_unit_name "$d")
    if systemd_unit_is_active "$unit"; then
        sudo systemctl stop "$unit" 2>/dev/null || systemctl stop "$unit" 2>/dev/null || true
    fi
}

systemd_start_all() {
    systemd_units_sync >/dev/null 2>&1 || true
    local d
    while IFS= read -r d; do
        systemd_instance_start "$d" || echo -e "${RED}Could not start $(basename "$d") — check: systemctl status $(systemd_unit_name "$d")${RESET}"
    done < <(psiphon_dirs)
}

systemd_stop_all() {
    local d
    while IFS= read -r d; do
        systemd_instance_stop "$d"
    done < <(psiphon_dirs)
}

systemd_restart_all() {
    systemd_stop_all
    sleep 1
    systemd_start_all
}

# systemd_unit_remove <dir> — stop + disable + delete the unit file,
# delete the per-instance user, daemon-reload. Best-effort throughout.
systemd_unit_remove() {
    local d="$1" unit user
    unit=$(systemd_unit_name "$d")
    user=$(systemd_instance_user "$d")
    systemd_instance_stop "$d"
    sudo systemctl disable "$unit" >/dev/null 2>&1 || true
    sudo rm -f "$SYSTEMD_UNIT_DIR/$unit"
    sudo systemctl daemon-reload 2>/dev/null || true
    if id -u "$user" >/dev/null 2>&1; then
        sudo userdel "$user" 2>/dev/null || true
    fi
}

# systemd_units_sync — reconcile units with the folders on disk:
#  - every instance dir gets its user + unit (no start — doctor must
#    never start a stopped instance on its own)
#  - units whose folder is gone are removed (with their user)
#  - stale v2.2 artefacts are removed: start-psiphons.sh, per-instance
#    start.sh, psiphon.firejail.pid files
#  - the dead oneshot autostart service is disabled + removed
systemd_units_sync() {
    local d unit base
    # 1) units for existing folders
    while IFS= read -r d; do
        systemd_unit_ensure "$d" || echo -e "${YELLOW}Could not ensure the unit for $(basename "$d").${RESET}"
        rm -f "$d/start.sh" "$d/psiphon.firejail.pid"
    done < <(psiphon_dirs)
    # 2) units whose folder is gone (unit multifon-psiphon-cz.service
    #    belongs to folder psiphon-cz — strip the multifon- prefix)
    shopt -s nullglob
    for unit in "$SYSTEMD_UNIT_DIR"/multifon-psiphon-*.service; do
        base=$(basename "$unit" .service)
        base="${base#multifon-}"
        if [[ ! -d "$PSIPHON_BASE_DIR/psiphon/$base" ]]; then
            echo -e "${YELLOW}Removing orphan unit: $(basename "$unit") (folder gone).${RESET}"
            sudo systemctl disable "$(basename "$unit")" >/dev/null 2>&1 || true
            sudo rm -f "$unit"
        fi
    done
    shopt -u nullglob
    sudo systemctl daemon-reload 2>/dev/null || true
    # 3) stale v2.2 launcher script
    rm -f "$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
    # 4) dead oneshot autostart service
    if [[ -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT" ]]; then
        echo -e "${YELLOW}Removing the dead oneshot autostart service $LEGACY_AUTOSTART_UNIT (per-instance units replace it).${RESET}"
        sudo systemctl disable --now "$LEGACY_AUTOSTART_UNIT" >/dev/null 2>&1 || true
        sudo rm -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT"
        sudo systemctl daemon-reload 2>/dev/null || true
    fi
}

# --- Status ------------------------------------------------------------------
# systemd_units_status — one line per instance: unit state + live pid.
systemd_units_status() {
    echo -e "${YELLOW}Psiphon instances (systemd units):${RESET}"
    local any=0 d unit st pid state
    while IFS= read -r d; do
        any=1
        unit=$(systemd_unit_name "$d")
        read -r _hp sp < <(instance_ports "$d")
        # v2.3.1: a failed unit and a restart-looping unit are NOT
        # "STOPPED" — show them as what they are, or the failure is
        # invisible in the menu (that is how the 90-byte binary hid).
        state=$(systemd_unit_state "$unit")
        case "$state" in
            RUNNING) st="${GREEN}RUNNING${RESET}" ;;
            FAILED*|RESTART-LOOP*) st="${RED}$state${RESET}" ;;
            "NO UNIT") st="${YELLOW}NO UNIT${RESET}" ;;
            STARTING) st="${YELLOW}STARTING${RESET}" ;;
            *) st="${RED}STOPPED${RESET}" ;;
        esac
        pid=$(psiphon_live_pid "$d" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            echo -e " $st  $(basename "$d")  ${WHITE}(HTTP:$_hp SOCKS:$sp, pid $pid, $unit)${RESET}"
        else
            echo -e " $st  $(basename "$d")  ${WHITE}(HTTP:$_hp SOCKS:$sp, $unit)${RESET}"
        fi
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
}

# systemd_units_summary — "N total, M active" for the menu status line.
systemd_units_summary() {
    local total=0 active=0 d unit
    while IFS= read -r d; do
        total=$((total + 1))
        unit=$(systemd_unit_name "$d")
        systemd_unit_is_active "$unit" && active=$((active + 1))
    done < <(psiphon_dirs)
    printf '%s total, %s active' "$total" "$active"
}

# --- One-time Firejail removal + migration ----------------------------------
# systemd_remove_firejail — the v2.3 migration, run once from menu 2
# (or menu 4 -> 2 / menu 10 -> 2):
#  1) stop any firejail psiphon processes still running (clean slate on
#     hamidr's server: none — but the code must be correct in general)
#  2) disable + remove the dead oneshot autostart service
#  3) purge the firejail + firejail-profiles packages
#  4) show the `apt autoremove --dry-run` list first, confirm, then
#     `apt autoremove --purge` — that is what frees the ~1 GB of
#     Recommends junk (xpra + GTK/GL dev stack) the v2.0 install pulled
#  5) remove the stale v2.1 sandbox-uid marker (gid rules replace it)
#  6) re-create every surviving instance folder as a systemd unit and
#     start it
# Prints disk space before/after so the freed ~1 GB is visible.
systemd_remove_firejail() {
    echo -e "${CYAN}${BOLD}Removing Firejail — the systemd units are the sandbox now.${RESET}"
    echo ""
    echo -e "${YELLOW}Disk before:${RESET}"
    df -h / | tail -n1
    echo ""

    # 1) stop firejail psiphon processes (live-pid match, not the unit —
    #    these processes predate the units)
    local pid
    for pid in $(pgrep -f "psiphon-tunnel-core" 2>/dev/null || true); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "firejail"; then
            echo -e "${YELLOW}Stopping firejail process $pid...${RESET}"
            _kill_pid "$pid"
        fi
    done
    # Any remaining core process with an instance folder as cwd.
    local d
    while IFS= read -r d; do
        pid=$(psiphon_live_pid "$d" || true)
        [[ -n "$pid" ]] && _kill_pid "$pid"
        rm -f "$d/psiphon.firejail.pid" "$d/start.sh"
    done < <(psiphon_dirs)

    # 2) dead oneshot autostart service
    if [[ -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT" ]]; then
        echo -e "${CYAN}Removing the old autostart service $LEGACY_AUTOSTART_UNIT...${RESET}"
        sudo systemctl disable --now "$LEGACY_AUTOSTART_UNIT" >/dev/null 2>&1 || true
        sudo rm -f "$SYSTEMD_UNIT_DIR/$LEGACY_AUTOSTART_UNIT"
        sudo systemctl daemon-reload 2>/dev/null || true
    fi
    rm -f "$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"

    # 3) purge the packages (best-effort if already gone)
    if command -v firejail >/dev/null 2>&1 || dpkg -l firejail 2>/dev/null | grep -q '^ii'; then
        echo -e "${CYAN}Purging firejail + firejail-profiles...${RESET}"
        sudo apt purge -y firejail firejail-profiles || echo -e "${YELLOW}apt purge had an issue — continuing anyway.${RESET}"
    else
        echo -e "${GREEN}Firejail is already gone.${RESET}"
    fi

    # 4) autoremove the ~1 GB of Recommends junk — dry-run first.
    echo ""
    echo -e "${YELLOW}These packages would be autoremoved (the xpra + GTK/GL stack Firejail dragged in):${RESET}"
    sudo apt autoremove --dry-run 2>/dev/null | sed -n '/will be REMOVED/,/^$/p' | head -n 20
    echo ""
    if confirm_yes "Run apt autoremove --purge now (frees ~1 GB)?"; then
        sudo apt autoremove --purge -y || echo -e "${YELLOW}autoremove had an issue — check apt output above.${RESET}"
    else
        echo -e "${YELLOW}Skipped autoremove — the junk stays until you run it (sudo apt autoremove --purge).${RESET}"
    fi

    # 5) stale v2.1 marker (gid rules replace the uid rules)
    rm -f "$SANDBOX_UID_FILE_LEGACY"

    # 6) re-create surviving folders as systemd units and start them
    echo ""
    echo -e "${CYAN}Re-creating surviving instances as systemd units...${RESET}"
    while IFS= read -r d; do
        echo -e " $(basename "$d")..."
        systemd_instance_apply "$d" || echo -e "${RED}Could not start $(basename "$d") — check: systemctl status $(systemd_unit_name "$d")${RESET}"
    done < <(psiphon_dirs)

    echo ""
    echo -e "${YELLOW}Disk after:${RESET}"
    df -h / | tail -n1
    echo ""
    echo -e "${GREEN}Firejail removal done. Sandbox is systemd units now — check with menu 3 -> 2.${RESET}"
}

# systemd_menu — main menu 2: the sandbox entry.
systemd_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Sandbox — systemd units (Firejail was removed in v2.3):${RESET}"
        systemd_units_status
        echo ""
        echo -e "${BLUE} 1) Re-sync all units ${WHITE}(create missing units/users, remove orphans)${RESET}"
        echo -e "${BLUE} 2) Remove Firejail + free ~1 GB ${WHITE}(one-time migration, dry-run first)${RESET}"
        echo -e "${BLUE} 3) Show one unit file${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-3]: " sd_opt
        case $sd_opt in
            1) systemd_units_sync; pause ;;
            2) systemd_remove_firejail; pause ;;
            3)
                d=$(select_psiphon_dir "Show the unit for which location?" || true)
                if [[ -n "$d" ]]; then
                    sudo cat "$SYSTEMD_UNIT_DIR/$(systemd_unit_name "$d")" 2>/dev/null \
                        || echo -e "${RED}No unit file for $(basename "$d") yet — run option 1.${RESET}"
                    pause
                fi
                ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}
