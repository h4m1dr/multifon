#!/bin/bash
# multifon v2 — lib/cores.sh
# Core loader (bug #8): every egress core exposes a SOCKS5 port (and an
# HTTP port where it has one). The menu treats all cores uniformly — a core
# is just a name + a SOCKS port + a start/stop function.
# The manifest lives in cores.yaml (human-readable source of truth);
# the functions below read it, so adding a core = one YAML block + one
# start/stop pair here. Nothing is downloaded at install time of multifon
# itself — core binaries are fetched on demand, with a prompt, in Phase 4.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_CORES_LOADED:-}" ]] && return 0
_MULTIFON_CORES_LOADED=1

CORES_FILE="$MULTIFON_DIR/cores.yaml"

# core_field <core-name> <field> — read one value from cores.yaml.
# cores.yaml is kept flat on purpose (2-space list items, 4-space fields)
# so this tiny awk parser stays reliable without yq/python.
core_field() {
    local name="$1" field="$2"
    [ -f "$CORES_FILE" ] || return 1
    awk -v name="$name" -v field="$field" '
        /^  - name: / { cur=""; sub(/^  - name: /, ""); cur=$0; next }
        cur == name && $0 ~ "^    " field ": " { sub("^    " field ": ", ""); print; exit }
    ' "$CORES_FILE"
}

# List core names from the manifest, one per line.
cores_list() {
    [ -f "$CORES_FILE" ] || return 0
    grep -E '^  - name: ' "$CORES_FILE" | sed 's/^  - name: //'
}

# One-line status for a core: manifest status + whether its binary exists.
core_status_line() {
    local name="$1" status binary bin_path
    status=$(core_field "$name" "status" || true)
    binary=$(core_field "$name" "binary" || true)
    bin_path=""
    [[ -n "$binary" ]] && bin_path=$(command -v "$binary" 2>/dev/null || true)
    if [[ -n "$bin_path" ]]; then
        echo -e " ${GREEN}●${RESET} $name  [${status}]  binary: $bin_path"
    else
        echo -e " ${RED}○${RESET} $name  [${status}]  binary: not installed"
    fi
}

cores_show_all() {
    echo -e "${YELLOW}Cores (from cores.yaml):${RESET}"
    local name
    for name in $(cores_list); do
        core_status_line "$name"
    done
    echo ""
    echo -e "${CYAN}Every core exposes a SOCKS5 port; the menu and the DNS rules treat them the same.${RESET}"
}

# --- WARP via wireproxy (test-only, Phase 4) -------------------------------
# wireproxy is a userspace WireGuard client that exposes a SOCKS5/HTTP
# proxy with no kernel interface and no root. Cloudflare WARP runs over it.
# Known limit (upstream TODO): SOCKS5 UDP is not supported yet, so WARP
# through wireproxy can carry TCP + DNS-over-TCP/DoH, but not raw UDP.
# Canonical repo is windtf/wireproxy (transferred home of
# pufferffish/wireproxy). WARP is marked test-only: hamidr's experience
# is that it usually does not respond — run docs/TEST-WARP-TOR.md first.
core_install_warp() {
    echo -e "${YELLOW}WARP core (experimental)${RESET}"
    if command -v wireproxy >/dev/null 2>&1; then
        echo -e "${GREEN}wireproxy is already installed: $(command -v wireproxy)${RESET}"
    else
        echo -e "${CYAN}wireproxy is fetched from its GitHub releases (windtf/wireproxy —${RESET}"
        echo -e "${CYAN}the transferred home of pufferffish/wireproxy).${RESET}"
        echo -e "${CYAN}The installer discovers the latest linux/amd64 asset — no version is hardcoded here.${RESET}"
        if ! confirm_yes "Download and install wireproxy now?"; then
            echo "Aborted."; return 1
        fi
        local tag asset_url tmp
        tmp=$(mktemp -d)
        tag=$(curl -s https://api.github.com/repos/windtf/wireproxy/releases/latest \
              | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
        if [[ -z "$tag" ]]; then
            echo -e "${RED}Could not read the latest wireproxy release.${RESET}"
            rm -rf "$tmp"; return 1
        fi
        asset_url=$(curl -s "https://api.github.com/repos/windtf/wireproxy/releases/tags/$tag" \
              | grep '"browser_download_url"' | grep -i 'linux.*amd64.*\.tar\.gz' | head -n1 \
              | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
        if [[ -z "$asset_url" ]]; then
            echo -e "${RED}No linux/amd64 tarball found for wireproxy $tag.${RESET}"
            rm -rf "$tmp"; return 1
        fi
        echo -e "${BLUE}Downloading $asset_url ...${RESET}"
        if ! curl -sL -o "$tmp/wireproxy.tgz" "$asset_url"; then
            echo -e "${RED}Download failed.${RESET}"
            rm -rf "$tmp"; return 1
        fi
        tar -xzf "$tmp/wireproxy.tgz" -C "$tmp"
        sudo install -m 0755 "$tmp/wireproxy" /usr/local/bin/wireproxy
        rm -rf "$tmp"
        echo -e "${GREEN}wireproxy installed. Next step: register a WARP account with wgcf and generate wireproxy.conf — see docs/TEST-WARP-TOR.md.${RESET}"
    fi
    echo -e "${YELLOW}WARP is TEST-ONLY (see cores.yaml + docs/TEST-WARP-TOR.md): run the test${RESET}"
    echo -e "${YELLOW}procedure first — if it fails, WARP moves to Phase before 6 or is dropped.${RESET}"
}

# --- Tor (test-only, Phase 4) ----------------------------------------------
core_install_tor() {
    echo -e "${YELLOW}Tor core (test-only)${RESET}"
    echo -e "${CYAN}Tor exposes a SOCKS5 port (default 9050). Tor exit IPs are heavily${RESET}"
    echo -e "${CYAN}blocked by Google/AI services — use it for anonymity, not for a clean score.${RESET}"
    echo -e "${CYAN}Ubuntu's tor package lags upstream; the Tor Project's own repo${RESET}"
    echo -e "${CYAN}(deb.torproject.org) is the newer source, but adding a third-party apt${RESET}"
    echo -e "${CYAN}source needs hamidr's review first — this installer uses the Ubuntu package.${RESET}"
    if command -v tor >/dev/null 2>&1; then
        echo -e "${GREEN}tor is already installed: $(command -v tor)${RESET}"
    else
        if ! confirm_yes "Install tor with apt now?"; then
            echo "Aborted."; return 1
        fi
        sudo apt update && sudo apt install -y tor
    fi
    echo -e "${YELLOW}Tor start/stop: systemctl start/stop tor@default (see docs/TEST-WARP-TOR.md).${RESET}"
    echo -e "${YELLOW}Tor is TEST-ONLY: run the test procedure first — if Gemini refuses it${RESET}"
    echo -e "${YELLOW}(the expected outcome), Tor stays a fallback core only.${RESET}"
}

# --- Geph (stub, Phase 4) --------------------------------------------------
core_install_geph() {
    echo -e "${YELLOW}Geph core (stub)${RESET}"
    echo -e "${CYAN}Geph (geph4-client) is listed in cores.yaml as experimental, but its${RESET}"
    echo -e "${CYAN}upstream binary location is not confirmed yet — the installer refuses${RESET}"
    echo -e "${CYAN}rather than downloading from a guessed URL. Confirm the upstream repo${RESET}"
    echo -e "${CYAN}and wire it here in Phase 4.${RESET}"
    return 1
}

# --- Arman VPN (stub, Phase 4) ---------------------------------------------
# Arman VPN is a free, open-source VPN that works with a Firefox Account:
# traffic goes through Mozilla's servers on Fastly infrastructure,
# 50 GB/month per Firefox Account, country choice with a ping test, and
# Firefox's own TLS fingerprint (uTLS). It is the "Firefox VPN" core
# from the Obsidian bug list (#8).
# Headless/server use was VERIFIED feasible by research (2026-11-24,
# ~/workspace/multifon-research/05-arman-vpn-headless.md): the Core is
# the server variant — SOCKS5 (and HTTP proxy) on 127.0.0.1:10810, CLI
# (arman-vpn-core -add-account / -list-accounts / -data-dir / -plain /
# -setup-server) + web panel on 10820, multi-account rotation at 95%.
# It is still a STUB here because two things are unverified before wiring:
# the exact config.json key for the SOCKS username/password (generated at
# setup, printed in the log), and whether the proxy/panel ports are
# configurable (two instances side by side). What wiring needs: a Firefox
# Account (no token or credential belongs in this repo), a one-time
# sign-in — try the panel first; if Mozilla's check refuses a non-browser
# sign-in, sign in on his Windows/Android app ("Sign in with the browser")
# and move the backup zip to the server via scp — and the SOCKS endpoint
# above. 50 GB/month per account is a hard limit to plan around
# (Psiphon has no such cap).
core_install_arman() {
    echo -e "${YELLOW}Arman VPN core (stub)${RESET}"
    echo -e "${CYAN}Free, open-source VPN on a Firefox Account — Mozilla servers${RESET}"
    echo -e "${CYAN}on Fastly, 50 GB/month per account, country choice with ping test.${RESET}"
    echo -e "${CYAN}Headless use IS verified feasible (research 2026-11-24): the server${RESET}"
    echo -e "${CYAN}variant exposes SOCKS5 on 127.0.0.1:10810 + a web panel on 10820.${RESET}"
    echo -e "${RED}Not wired yet: the config.json key for the SOCKS credentials and${RESET}"
    echo -e "${RED}whether the ports are configurable are still unverified, and the${RESET}"
    echo -e "${RED}one-time sign-in needs hamidr (panel first, or the browser sign-in +${RESET}"
    echo -e "${RED}backup move via scp). See docs/PHASES.md Phase 4. No account or token${RESET}"
    echo -e "${RED}goes in this repo.${RESET}"
    return 1
}

# Dispatch install by core name.
core_install() {
    local name="$1"
    case "$name" in
        psiphon) install_psiphon_menu ;;
        warp)    core_install_warp ;;
        tor)     core_install_tor ;;
        geph)    core_install_geph ;;
        arman)   core_install_arman ;;
        *) echo -e "${RED}Unknown core: $name${RESET}"; return 1 ;;
    esac
}
