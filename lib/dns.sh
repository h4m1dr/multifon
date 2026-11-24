#!/bin/bash
# multifon v2 — lib/dns.sh
# Force DNS: every core's DNS must leave through the SAME SOCKS as its
# TCP traffic, so no proxy poured onto the server can leak DNS.
#
# Why not dns2socks: it sends DNS over SOCKS5 UDP associate, and Psiphon
# SOCKS does not support UDP associate — it would fail outright. The only
# reliable path is DNS over TCP: DNS-over-HTTPS (DoH) through the SOCKS
# proxy with --socks5-hostname, so even the DNS server name resolves
# inside the tunnel.
#
# This file is the Phase 4 foundation:
#  - dns_leak_check <socks-port>: proves DoH works through the proxy and
#    tests whether direct UDP/53 is reachable from an instance user
#    (the leak path).
#  - dns_force_enable/disable: the SCOPED iptables rules on port 53 +
#    STUN (in lib/firewall.sh) — owner-match on the `multifon` group
#    (one user per instance, see lib/systemd.sh), so Xray's own DNS
#    keeps working. The v2.0 server-wide block is gone.
#  - a per-instance DoH query helper + a per-egress dnscrypt-proxy
#    forwarder (Phase 4, wired below), so each core gets a local DNS
#    listener whose queries leave through that core — never plain UDP/53.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_DNS_LOADED:-}" ]] && return 0
_MULTIFON_DNS_LOADED=1

# DoH query through one SOCKS port (JSON API, no binary DNS needed).
# Usage: dns_doh_query <socks-port> <hostname> [type] -> prints the answer IPs.
dns_doh_query() {
    local socks="$1" host="$2" type="${3:-A}"
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    curl -s --max-time 10 --socks5-hostname "127.0.0.1:$socks" \
        "https://dns.google/resolve?name=$host&type=$type" \
        | jq -r '.Answer[]?.data // empty' 2>/dev/null
}

# Leak check for one SOCKS port.
#  1) DoH through the proxy must answer (DNS-via-tunnel works).
#  2) Direct UDP/53 must NOT answer (otherwise DNS can bypass the proxy).
# Usage: dns_leak_check <socks-port> [instance-dir]
# The instance dir selects the probe user: each instance is probed as
# ITS OWN user (multifon-<cc>), never as another instance's user.
dns_leak_check() {
    local socks="$1" dir="${2:-}" ans
    [[ "$socks" =~ ^[0-9]+$ ]] || { echo -e "${RED}Bad SOCKS port: $socks${RESET}"; return 1; }
    echo -e "${YELLOW}DNS leak check for SOCKS 127.0.0.1:$socks${RESET}"

    ans=""
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        ans=$(dns_doh_query "$socks" "example.com" "A" || true)
    else
        echo -e " ${YELLOW}DoH test needs curl + jq — skipping (install jq to run it).${RESET}"
    fi
    if [[ -n "$ans" ]]; then
        echo -e " ${GREEN}DoH through the proxy works:${RESET} example.com -> $ans"
    elif command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        echo -e " ${RED}DoH through the proxy FAILED — DNS for this egress is broken.${RESET}"
    fi

    # Direct-DNS probe: a real query to a resolver that is NOT on the
    # bootstrap allow-list (208.67.222.222). It must run AS AN INSTANCE
    # USER when the scoped block is set up — a probe as root would bypass
    # the owner-match rules entirely and report a false "leak".
    # (A bash /dev/udp open would NOT detect the block — UDP connect
    # succeeds locally even when the packet is dropped — so dig is used.)
    # v2.3.3: the probe runs with the unit's gid too (sudo -u <user> -g
    # multifon) so it models the sandboxed process exactly, not the
    # login primary gid. And the message must never say "enable the
    # block" when the block is already on: if the probe answers while
    # the status says blocked, the rules exist but are not catching
    # this traffic (v2.3.1: they sat below the UFW jumps) — that is a
    # different problem from "block is off".
    if command -v dig >/dev/null 2>&1; then
        local probe_cmd="dig" probe_sudo="sudo" probe_user=""
        if [[ -n "$dir" ]]; then
            probe_user=$(systemd_instance_user "$dir" 2>/dev/null || true)
            if [[ -n "$probe_user" ]] && ! id -u "$probe_user" >/dev/null 2>&1; then
                probe_user=""
            fi
        fi
        [[ -z "$probe_user" ]] && probe_user=$(systemd_first_instance_user || true)
        if [[ -n "$probe_user" ]]; then
            probe_sudo="sudo -u $probe_user"
            if getent group "$SANDBOX_GROUP" >/dev/null 2>&1; then
                probe_sudo="sudo -u $probe_user -g $SANDBOX_GROUP"
            fi
            probe_cmd="$probe_sudo dig"
            echo -e " Probing as instance user $probe_user (group $SANDBOX_GROUP — the gid the scoped rules match)."
        else
            echo -e " ${YELLOW}No instance user exists yet (no psiphon-* folder) — probing as the current user (host view, not the sandbox).${RESET}"
        fi
        local block_status
        block_status=$(dns_leak_block_status)
        if timeout 5 $probe_cmd +short +time=3 +tries=1 "@$DNS_PROBE_RESOLVER" example.com >/dev/null 2>&1; then
            if [[ "$block_status" == blocked* ]]; then
                echo -e " ${RED}LEAK PATH OPEN: direct DNS to $DNS_PROBE_RESOLVER:53 answers — but the scoped block is ON ($block_status). The rules exist but are NOT catching this traffic: check rule order (sudo iptables -L OUTPUT -n -v --line-numbers) and re-enable once to move them to the top of OUTPUT.${RESET}"
            else
                echo -e " ${RED}LEAK PATH OPEN: direct DNS to $DNS_PROBE_RESOLVER:53 answers. Enable the scoped port-53 block (dns_force_enable).${RESET}"
            fi
        else
            echo -e " ${GREEN}Direct DNS to $DNS_PROBE_RESOLVER:53 does not answer — no plain-DNS leak path to arbitrary resolvers.${RESET}"
        fi
        # Bootstrap path must still work for the instance user.
        if [[ -n "$probe_user" ]]; then
            if timeout 5 $probe_sudo dig +short +time=3 +tries=1 @1.1.1.1 example.com >/dev/null 2>&1; then
                echo -e " ${GREEN}Bootstrap DNS still works for $probe_user (1.1.1.1 allowed).${RESET}"
            else
                echo -e " ${RED}Bootstrap DNS is broken for $probe_user — the core cannot resolve its server list. Check the allow-list rules.${RESET}"
            fi
        fi
    else
        echo -e " ${YELLOW}dig is not installed — direct-DNS probe skipped. Port-53 block status: $(dns_leak_block_status).${RESET}"
    fi

    local fw
    fw=$(dns_leak_block_status)
    echo -e " Port-53 firewall block: $fw"
    echo -e " STUN firewall block: $(stun_block_status)"
}

# Leak check for every RUNNING instance (v2.3.1: a stopped instance
# has no proxy to leak through and no DoH to fail — checking it only
# produces false alarms ("DoH FAILED", "LEAK PATH OPEN"). It is skipped
# with a plain "not running" line instead.
dns_leak_check_all() {
    local any=0
    while IFS= read -r d; do
        any=1
        read -r _hp sp < <(instance_ports "$d")
        echo -e "${CYAN}$(basename "$d"):${RESET}"
        if ! psiphon_live_pid "$d" >/dev/null 2>&1; then
            echo -e " ${YELLOW}not running — start it first (menu 3 -> 3). Skipping leak check.${RESET}"
            echo ""
            continue
        fi
        dns_leak_check "$sp" "$d" || true
        echo ""
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
}

# Enable the Force-DNS enforcement: the SCOPED port-53 + STUN block
# (see lib/firewall.sh). v2.3: the rules match ONLY the `multifon`
# group (one user per instance), so Xray keeps working — its DNS (plain
# 1.1.1.1 / 9.9.9.9 on port 53) runs as root and never matches the
# owner-match rules, and neither do apt or dig from the shell.
# Enabling once also removes any legacy server-wide (v2.0) or uid-owner
# (v2.1) rule left over from an earlier version.
dns_force_enable() {
    echo -e "${YELLOW}Scoped block: only the Psiphon sandboxes (group '$SANDBOX_GROUP') are affected.${RESET}"
    echo -e "${YELLOW}Xray / 3x-ui, apt and dig keep working — they run as root, not as '$SANDBOX_GROUP'.${RESET}"
    echo -e "${YELLOW}First enable creates the '$SANDBOX_GROUP' group, gives every instance its own user + unit, and restarts the running instances once.${RESET}"
    scoped_block_preview
    if ! confirm_yes "Enable the scoped port-53 + STUN block?"; then
        echo "Aborted."; return 1
    fi
    dns_leak_block_enable
}

dns_force_disable() {
    dns_leak_block_disable
}

dns_force_status() {
    echo -e "Port-53 firewall block: $(dns_leak_block_status)"
    echo -e "STUN firewall block: $(stun_block_status)"
    if sandbox_group_enabled; then
        echo -e "Sandbox group: $SANDBOX_GROUP (gid $(getent group "$SANDBOX_GROUP" | cut -d: -f3)) — one user per instance"
    else
        echo -e "Sandbox group: not set up yet (instances still run as root; enable the block once to set it up)"
    fi
}

# --- Per-egress DoH forwarder (Phase 4, dnscrypt-proxy) ---------------------
# One dnscrypt-proxy process per egress: it listens on 127.0.0.1:<dns-port>
# and sends every query as DoH through that egress's SOCKS port
# (proxy = 'socks5://…' + force_tcp = true). dnscrypt-proxy is the ONLY
# candidate with a native SOCKS5 upstream — dnsproxy has no SOCKS flag,
# cloudflared proxy-dns was removed in 2026.2.0, CoreDNS forward has no
# SOCKS option, socat 1.x has no SOCKS5, doh-client is gone (404).
# See ~/workspace/multifon-research/01-doh-forwarder.md.
#
# Layout: configs + pidfiles live in $PSIPHON_BASE_DIR/psiphon/.dns/
# (next to the instances — no root needed, travels with the instance data).
# Start order matters: the egress core must be up BEFORE its forwarder
# starts — a first-ever start with no cache and no proxy fails.
#
# Bootstrap lookup — no download, no bootstrap lookup at all (v2.3.3):
# the DoH server comes from a [static] stamp copied VERBATIM from the
# upstream public-resolvers list (DNSCrypt/dnscrypt-resolvers v3,
# `cloudflare` entry, 1.0.0.1) — verified with the real dnscrypt-proxy
# 2.0.45 binary (`-check` passes, process stays up and listens).
# No [sources] section on purpose: with sources, dnscrypt-proxy
# DOWNLOADS the resolver list at startup through the configured SOCKS
# proxy — if the egress is down, the forwarder exits before it ever
# serves (verified live: FATAL on the download when :1081 refused).
# And `bootstrap_resolvers` is NOT a valid key in 2.0.45 (it FATALs
# with "Unsupported key") — the correct 2.0.45 key is
# `fallback_resolvers` (upstream example-dnscrypt-proxy.toml line 228);
# it is only used if a stamp ever carries a hostname, which this one
# does not (IP embedded). Test on the server:
#   dig @127.0.0.1 -p <listen> example.com
#   tcpdump -i any udp port 53 and not host 127.0.0.1   # expect: nothing
# If that test shows a leak, the forwarder moves to Phase before 6.

DNS_DIR="$PSIPHON_BASE_DIR/psiphon/.dns"

# dns_doh_listen_port <socks-port> — the DNS listener port for an egress.
# Psiphon 1081-1090 -> 5353-5362; WARP 1091-1099 -> 5371-5379;
# Tor 9050 -> 5380; Arman 10810 -> 5381; anything else -> 5399.
# (The research note mapped WARP/Tor/Arman to 5361-5363, which collide
# with the tail of the Psiphon range — this scheme has no collisions.)
dns_doh_listen_port() {
    local socks="$1"
    if [[ "$socks" == "9050" ]]; then echo 5380; return 0; fi
    if [[ "$socks" == "10810" ]]; then echo 5381; return 0; fi
    if [[ "$socks" -ge 1081 && "$socks" -le 1090 ]] 2>/dev/null; then echo $((5353 + socks - 1081)); return 0; fi
    if [[ "$socks" -ge 1091 && "$socks" -le 1099 ]] 2>/dev/null; then echo $((5371 + socks - 1091)); return 0; fi
    echo 5399
}

# dns_forwarder_config <socks-port> [name] [listen-port]
# Write the toml for one egress. Prints the toml path. Idempotent.
dns_forwarder_config() {
    local socks="$1" name="${2:-socks$socks}" listen="${3:-}"
    [[ -z "$listen" ]] && listen=$(dns_doh_listen_port "$socks")
    mkdir -p "$DNS_DIR"
    local toml="$DNS_DIR/dnscrypt-proxy-$name.toml"
    cat > "$toml" <<EOF
# Generated by multifon — per-egress DoH forwarder (dnscrypt-proxy).
# Egress SOCKS 127.0.0.1:$socks -> DNS listener 127.0.0.1:$listen.
# Do not edit by hand; regenerate with dns_forwarder_config.
# Validated against dnscrypt-proxy 2.0.45 (the version Ubuntu 24.04
# ships): "bootstrap_resolvers" is NOT a key in 2.0.45 (FATAL) — the
# correct key is "fallback_resolvers". The server comes from a [static]
# stamp, so no [sources] download is needed at startup (see lib/dns.sh
# header comment). Stamp copied verbatim from
# DNSCrypt/dnscrypt-resolvers v3 public-resolvers.md, "cloudflare".
listen_addresses = ['127.0.0.1:$listen']
server_names = ['cloudflare']
doh_servers = true
proxy = 'socks5://127.0.0.1:$socks'
force_tcp = true
cache = true
fallback_resolvers = ['1.1.1.1:53', '8.8.8.8:53']
[static]
  [static.'cloudflare']
  stamp = 'sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5'
EOF
    echo "$toml"
}

# dns_forwarder_install — make sure dnscrypt-proxy exists.
# Ubuntu 24.04 package availability was NOT verifiable during research:
# if apt has no candidate, the function says so and points at the
# upstream releases page instead of guessing.
dns_forwarder_install() {
    if command -v dnscrypt-proxy >/dev/null 2>&1; then
        echo -e "${GREEN}dnscrypt-proxy is already installed: $(command -v dnscrypt-proxy)${RESET}"
        return 0
    fi
    echo -e "${CYAN}dnscrypt-proxy is not installed.${RESET}"
    if ! confirm_yes "Install it with apt now?"; then
        echo "Aborted."
        return 1
    fi
    # NOTE (known packaging warning, not a multifon bug): on this box
    # apt prints "Could not execute systemctl: at
    # /usr/bin/deb-systemd-invoke line 148." while configuring the
    # package. The package still installs fine — the postinst cannot
    # talk to systemd from the apt context. No action needed; do not
    # try to "fix" apt/dpkg behaviour here.
    if sudo apt update && sudo apt install -y dnscrypt-proxy; then
        if command -v dnscrypt-proxy >/dev/null 2>&1; then
            echo -e "${GREEN}dnscrypt-proxy installed.${RESET}"
            return 0
        fi
    fi
    echo -e "${RED}apt install failed or the package has no candidate on this Ubuntu.${RESET}"
    echo -e "${YELLOW}Install the release binary by hand: https://github.com/DNSCrypt/dnscrypt-proxy/releases${RESET}"
    return 1
}

# dns_forwarder_start <socks-port> [listen-port] [name]
# Writes the toml, starts dnscrypt-proxy in the background, records the
# pid, and verifies the listener answers with dig (if dig exists).
# The egress core must already be running — start order: core first.
dns_forwarder_start() {
    local socks="$1" listen="${2:-}" name="${3:-socks$socks}"
    [[ "$socks" =~ ^[0-9]+$ ]] || { echo -e "${RED}Usage: dns_forwarder_start <socks-port> [listen-port] [name]${RESET}"; return 1; }
    command -v dnscrypt-proxy >/dev/null 2>&1 || { echo -e "${RED}dnscrypt-proxy is not installed — run dns_forwarder_install first (menu 8 -> 4).${RESET}"; return 1; }
    if ! port_in_use "$socks"; then
        echo -e "${RED}Nothing is listening on SOCKS $socks — start the egress core first, then its forwarder.${RESET}"
        return 1
    fi
    [[ -z "$listen" ]] && listen=$(dns_doh_listen_port "$socks")
    local toml pidfile
    toml=$(dns_forwarder_config "$socks" "$name" "$listen")
    pidfile="$DNS_DIR/dnscrypt-proxy-$name.pid"
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
        echo -e "${YELLOW}Forwarder for $name is already running (pid $(cat "$pidfile")).${RESET}"
        return 0
    fi
    local logfile="$DNS_DIR/dnscrypt-proxy-$name.log"
    # Validate the config BEFORE starting: a bad toml kills the process
    # instantly (v2.3.1: `bootstrap_resolvers` FATALed in 2.0.45 and the
    # only message was "check the config"). -check prints the real error.
    local check_out
    if ! check_out=$(dnscrypt-proxy -check -config "$toml" 2>&1); then
        echo -e "${RED}dnscrypt-proxy config check failed for $name:${RESET}"
        echo "$check_out" | tail -n 5
        echo -e "${YELLOW}Config: $toml${RESET}"
        return 1
    fi
    rm -f "$logfile"
    nohup dnscrypt-proxy -config "$toml" >>"$logfile" 2>&1 &
    echo $! > "$pidfile"
    sleep 2
    if kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo -e "${GREEN}DoH forwarder up:${RESET} $name — SOCKS $socks -> DNS 127.0.0.1:$listen (pid $(cat "$pidfile"))"
    else
        echo -e "${RED}dnscrypt-proxy for $name exited — last log lines ($logfile):${RESET}"
        tail -n 5 "$logfile" 2>/dev/null || echo "  (no log output)"
        echo -e "${YELLOW}Config: $toml${RESET}"
        rm -f "$pidfile"
        return 1
    fi
    if command -v dig >/dev/null 2>&1; then
        if timeout 5 dig +short +time=3 +tries=1 @127.0.0.1 -p "$listen" example.com >/dev/null 2>&1; then
            echo -e " ${GREEN}Listener answers: dig @127.0.0.1 -p $listen example.com works.${RESET}"
        else
            echo -e " ${YELLOW}Listener does not answer yet — the egress may be down, or the bootstrap lookup failed. See docs/PHASES.md (Phase before 6).${RESET}"
        fi
    fi
}

# dns_forwarder_stop <name> — stop one forwarder by its config name.
dns_forwarder_stop() {
    local name="$1" pidfile="$DNS_DIR/dnscrypt-proxy-$1.pid" pid="" p=""
    [[ -f "$pidfile" ]] && pid=$(cat "$pidfile" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo -e "${GREEN}Stopped DoH forwarder $name (pid $pid).${RESET}"
    else
        # Fall back to matching the process by its config path.
        p=$(pgrep -f "dnscrypt-proxy.*dnscrypt-proxy-$name.toml" 2>/dev/null | head -n1 || true)
        if [[ -n "$p" ]]; then
            kill "$p" 2>/dev/null
            echo -e "${GREEN}Stopped DoH forwarder $name (pid $p).${RESET}"
        else
            echo -e "${YELLOW}No running forwarder found for $name.${RESET}"
        fi
    fi
    rm -f "$pidfile"
}

dns_forwarder_stop_all() {
    local any=0 toml
    shopt -s nullglob
    for toml in "$DNS_DIR"/dnscrypt-proxy-*.toml; do
        any=1
        dns_forwarder_stop "$(basename "$toml" .toml | sed 's/^dnscrypt-proxy-//')"
    done
    shopt -u nullglob
    [ "$any" -eq 0 ] && echo -e "${YELLOW}No DoH forwarders configured.${RESET}"
}

# dns_forwarder_status — one line per configured forwarder.
dns_forwarder_status() {
    local any=0 toml name pid listen
    shopt -s nullglob
    for toml in "$DNS_DIR"/dnscrypt-proxy-*.toml; do
        any=1
        name=$(basename "$toml" .toml | sed 's/^dnscrypt-proxy-//')
        listen=$(grep -oE "127.0.0.1:[0-9]+" "$toml" | head -n1 | cut -d: -f2)
        pid=""
        [[ -f "$DNS_DIR/dnscrypt-proxy-$name.pid" ]] && pid=$(cat "$DNS_DIR/dnscrypt-proxy-$name.pid" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e " ${GREEN}●${RESET} $name  DNS 127.0.0.1:$listen  (pid $pid)"
        else
            echo -e " ${RED}○${RESET} $name  DNS 127.0.0.1:$listen  (not running)"
        fi
    done
    shopt -u nullglob
    [ "$any" -eq 0 ] && echo -e "${YELLOW}No DoH forwarders configured yet.${RESET}"
}

# dns_forwarder_start_all — one forwarder per RUNNING egress:
# every running Psiphon instance, plus WARP (1091), Tor (9050) and Arman
# (10810) when their SOCKS ports are listening.
dns_forwarder_start_all() {
    dns_forwarder_install || return 1
    # v2.3.3: running / started / failed are counted separately. The old
    # code printed "No running egresses" whenever zero forwarders
    # started — including when all three units were ACTIVE and every
    # forwarder had simply exited on a bad config. That message is now
    # only printed when genuinely nothing is running.
    local d sp name spec started=0 failed=0 running=0 skipped=0
    while IFS= read -r d; do
        read -r _hp sp < <(instance_ports "$d")
        [[ "$sp" =~ ^[0-9]+$ ]] || continue
        if ! psiphon_live_pid "$d" >/dev/null 2>&1; then
            echo -e "${YELLOW}$(basename "$d") is not running — skipping its forwarder.${RESET}"
            skipped=$((skipped + 1))
            continue
        fi
        running=$((running + 1))
        if dns_forwarder_start "$sp" "" "$(basename "$d")"; then
            started=$((started + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(psiphon_dirs)
    for spec in "warp:1091" "tor:9050" "arman:10810"; do
        name="${spec%%:*}"; sp="${spec##*:}"
        if port_in_use "$sp"; then
            running=$((running + 1))
            if dns_forwarder_start "$sp" "" "$name"; then
                started=$((started + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    if [[ "$running" -eq 0 ]]; then
        echo ""
        echo -e "${YELLOW}No running egresses — start the instances first (menu 3 -> 3), then run this again.${RESET}"
    elif [[ "$failed" -gt 0 ]]; then
        echo ""
        echo -e "${RED}$failed forwarder(s) failed to start (see the errors above) — $started running, $running egress(es) up.${RESET}"
    fi
    echo ""
    echo -e "${YELLOW}Bootstrap-lookup check (still needs a tcpdump test on the server):${RESET}"
    echo -e "  dig @127.0.0.1 -p <listen> example.com   # must answer"
    echo -e "  tcpdump -i any udp port 53 and not host 127.0.0.1   # expect: nothing"
}
