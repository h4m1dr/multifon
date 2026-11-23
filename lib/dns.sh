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
#    tests whether direct UDP/53 is reachable (the leak path).
#  - dns_force_enable/disable: the iptables OUTPUT block on port 53
#    (in lib/firewall.sh) — the enforcement switch.
#  - a per-instance DoH query helper + an optional socat forwarder, so a
#    local DNS listener can be served through one egress.
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
# Usage: dns_leak_check <socks-port>
dns_leak_check() {
    local socks="$1" ans
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

    # Direct UDP/53 probe: a real query to 8.8.8.8. If the port-53 OUTPUT
    # block is on, the query times out; if it is off, it answers.
    # (A bash /dev/udp open would NOT detect the block — UDP connect
    # succeeds locally even when the packet is dropped — so dig is used.)
    if command -v dig >/dev/null 2>&1; then
        if timeout 5 dig +short +time=3 +tries=1 @8.8.8.8 example.com >/dev/null 2>&1; then
            echo -e " ${RED}LEAK PATH OPEN: direct DNS to 8.8.8.8:53 answers. Enable the port-53 block (dns_force_enable).${RESET}"
        else
            echo -e " ${GREEN}Direct DNS to 8.8.8.8:53 does not answer — no plain-DNS leak path.${RESET}"
        fi
    else
        echo -e " ${YELLOW}dig is not installed — direct-DNS probe skipped. Port-53 block status: $(dns_leak_block_status).${RESET}"
    fi

    local fw
    fw=$(dns_leak_block_status)
    echo -e " Port-53 firewall block: $fw"
}

# Leak check for every running instance.
dns_leak_check_all() {
    local any=0
    while IFS= read -r d; do
        any=1
        read -r _hp sp < <(instance_ports "$d")
        echo -e "${CYAN}$(basename "$d"):${RESET}"
        dns_leak_check "$sp" || true
        echo ""
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
}

# Enable the Force-DNS enforcement: block direct port 53 (see firewall.sh).
# Prints a warning first — this also blocks plain dig/nslookup from the shell.
dns_force_enable() {
    echo -e "${YELLOW}This blocks ALL direct outbound DNS (UDP/TCP 53) on the server.${RESET}"
    echo -e "${YELLOW}System tools that use plain DNS (dig, apt without DoH) will stop working until you disable it.${RESET}"
    if ! confirm_yes "Enable the port-53 block?"; then
        echo "Aborted."; return 1
    fi
    dns_leak_block_enable
}

dns_force_disable() {
    dns_leak_block_disable
}

dns_force_status() {
    echo -e "Port-53 firewall block: $(dns_leak_block_status)"
}

# Optional local forwarder: serve DNS on 127.0.0.1:<listen-port> and answer
# every query with DoH through one instance's SOCKS port. Needs socat.
# Usage: dns_forwarder_start <socks-port> <listen-port>
dns_forwarder_start() {
    local socks="$1" listen="$2"
    command -v socat >/dev/null 2>&1 || {
        echo -e "${RED}socat is not installed — the forwarder needs it (sudo apt install socat).${RESET}"
        return 1
    }
    [[ "$socks" =~ ^[0-9]+$ && "$listen" =~ ^[0-9]+$ ]] || {
        echo -e "${RED}Usage: dns_forwarder_start <socks-port> <listen-port>${RESET}"
        return 1
    }
    # The helper script answers one DNS query per connection via DoH.
    # (Phase 4 will replace this with a persistent DoH forwarder.)
    echo -e "${YELLOW}Forwarder is a Phase 4 item: the DoH query helper exists (dns_doh_query),${RESET}"
    echo -e "${YELLOW}but a persistent per-egress listener is not wired yet. Use dns_leak_check to verify manually.${RESET}"
    return 1
}
