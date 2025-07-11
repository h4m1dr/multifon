#!/bin/bash

# colors
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

# Multi Psiphon logo
logo() {
clear
echo -e "${CYAN}${BOLD}"
echo -e "███╗   ███╗ ██████╗ ██╗   ██╗██╗     ████████╗██╗███████╗ ██████╗ ███╗   ██╗"
echo -e "████╗ ████║██╔═══██╗██║   ██║██║     ╚══██╔══╝██║██╔════╝██╔═══██╗████╗  ██║"
echo -e "██╔████╔██║██║   ██║██║   ██║██║        ██║   ██║█████╗  ██║   ██║██╔██╗ ██║"
echo -e "██║╚██╔╝██║██║   ██║██║   ██║██║        ██║   ██║██╔══╝  ██║   ██║██║╚██╗██║"
echo -e "██║ ╚═╝ ██║╚██████╔╝╚██████╔╝███████╗   ██║   ██║██║     ╚██████╔╝██║ ╚████║"
echo -e "╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
echo -e "                    ${WHITE}Multi Psiphon Manager${RESET}${CYAN}  | ${WHITE}github.com/SpherionOS/PsiphonLinux${RESET}"
echo ""
}

# status and location count
check_status() {
    [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]] && psi_status="${GREEN}✓ Installed${RESET}" || psi_status="${RED}✗ Not Found${RESET}"
    [[ -x "$(command -v firejail)" ]] && fj_status="${GREEN}✓ Installed${RESET}" || fj_status="${RED}✗ Not Found${RESET}"
    loc_count=$(find "$HOME/psiphon/" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l)
    
    echo -e "${YELLOW}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${YELLOW}${BOLD}│        ${WHITE}System Status Check${YELLOW}        │${RESET}"
    echo -e "${YELLOW}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${WHITE}• Psiphon:     ${psi_status}  ${CYAN}/usr/bin/psiphon-tunnel-core-x86_64${RESET}"
    echo -e " ${WHITE}• Firejail:    ${fj_status}"
    echo -e " ${WHITE}• Locations:   ${MAGENTA}$loc_count${RESET} created in ${CYAN}$HOME/psiphon${RESET}"
    echo -e " ${WHITE}• Source:      ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo ""
}

# Main menu
main_menu() {
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│          ${WHITE}Main Menu${MAGENTA}              │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Psiphon Installation Menu     ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e " ${CYAN}[2]${RESET} Install Firejail"
    echo -e " ${CYAN}[3]${RESET} Create Psiphon Folder with Firejail"
    echo -e " ${CYAN}[4]${RESET} Create Psiphon Folder without Firejail     ${RED}#Not recommended for multi-location use${RESET}"
    echo -e " ${CYAN}[5]${RESET} Show Running Psiphon Instances"
    echo -e " ${CYAN}[6]${RESET} Cleanup Options"
    echo -e " ${CYAN}[0]${RESET} Exit"
    echo ""
}

# Full show
logo
check_status
main_menu
