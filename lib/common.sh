#!/bin/bash
# multifon v2 — lib/common.sh
# Shared bits: colors, logo, pause, status, yes/no prompts.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_COMMON_LOADED:-}" ]] && return 0
_MULTIFON_COMMON_LOADED=1

MULTIFON_VERSION="2.1.0"

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
FIREJAIL_CONFIG_DIR="/etc/firejail"

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
    [[ -x "$(command -v firejail)" ]] && fj_status="${GREEN}✓ Installed${RESET}" || fj_status="${RED}✗ Not Found${RESET}"
    loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )

    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    echo -e " System Check:"
    echo -e " - Psiphon installed: ${psi_status} ${CYAN}(/usr/bin/psiphon)${RESET}"
    echo -e " - Firejail installed: ${fj_status}"
    echo -e " - Number of configured Psiphon locations: ${MAGENTA}$loc_count${RESET}"
    echo -e " - Psiphon source: ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    info_write_system
    echo ""
}
