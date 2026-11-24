#!/bin/bash
# multifon v2 — lib/common.sh
# Shared bits: colors, logo, pause, status, yes/no prompts.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_COMMON_LOADED:-}" ]] && return 0
_MULTIFON_COMMON_LOADED=1

MULTIFON_VERSION="2.3.1"

# Colors
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

# Directories (HOME is the Psiphon base, same as v1)
PSIPHON_BASE_DIR="$HOME"
# (v2.3: no FIREJAIL_CONFIG_DIR any more — Firejail is gone.)

# Multi Psiphon logo
logo() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo -e "             ███╗   ███╗██╗   ██╗██╗  ████████╗██╗ ███████╗ ██████╗ ███╗   ██╗"
    echo -e "             ████╗ ████║██║   ██║██║  ╚══██╔══╝██║ ██╔════╝██╔═══██╗████╗  ██║"
    echo -e "             ██╔████╔██║██║   ██║██║     ██║   ██║ █████╗  ██║   ██║██╔██╗ ██║"
    echo -e "             ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║ ██║     ╚██████╔╝██║ ╚████║"
    echo -e "             ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
    echo -e "                    ${WHITE}Multi Psiphon Manager v${MULTIFON_VERSION}${RESET}${CYAN}  | ${WHITE}Source: Psiphon SpherionOS ${RESET}"
    echo ""
}

# Helper: pause for input
pause() {
    echo ""
    read -n1 -s -r -p $'🔁 Press any key to continue...'
}

# Confirm helper — BUG FIX #2.
# Old code accepted only the exact string "YES".
# Now: lowercase + trim, accepts y / yes (any case). Default is NO.
# Usage: confirm_yes "Type yes to confirm"  -> 0 = yes, 1 = no
confirm_yes() {
    local prompt="${1:-Are you sure? (y/N)}" ans
    read -rp "$prompt [y/N]: " ans
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ "$ans" == "y" || "$ans" == "yes" ]]
}

# Status and Psiphon location count
check_status() {
    if [[ -x "/usr/bin/psiphon" ]] ; then
        psi_status="${GREEN}✓ Installed${RESET}"
    else
        psi_status="${RED}✗ Not Found${RESET}"
    fi
    local units_summary=""
    if command -v systemctl >/dev/null 2>&1; then
        units_summary=$(systemd_units_summary 2>/dev/null || true)
    fi
    loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )

    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    echo -e " System Check:"
    echo -e " - Psiphon installed: ${psi_status} ${CYAN}(/usr/bin/psiphon)${RESET}"
    echo -e " - Systemd units: ${CYAN}${units_summary:-not available (no systemctl)}${RESET}"
    echo -e " - Number of configured Psiphon locations: ${MAGENTA}$loc_count${RESET}"
    echo -e " - Psiphon source: ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    info_write_system
    echo ""
}
