#!/bin/bash

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
                    
# Multi Psiphon logo 
logo() {
clear
echo -e "${CYAN}${BOLD}"
echo -e "             ███╗   ███╗██╗   ██╗██╗  ████████╗██╗ ███████╗ ██████╗ ███╗   ██╗"
echo -e "             ████╗ ████║██║   ██║██║  ╚══██╔══╝██║ ██╔════╝██╔═══██╗████╗  ██║"
echo -e "             ██╔████╔██║██║   ██║██║     ██║   ██║ █████╗  ██║   ██║██╔██╗ ██║"
echo -e "             ██║╚██╔╝██║██║   ██║██║     ██║   ██║ ██╔══╝  ██║   ██║██║╚██╗██║"
echo -e "             ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║ ██║     ╚██████╔╝██║ ╚████║"
echo -e "             ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
echo -e "                    ${WHITE}Multi Psiphon Manager${RESET}${CYAN}  | ${WHITE}Source: Psiphon SpherionOS ${RESET}"
echo ""
}

# Helper: pause for input
pause() {
    echo ""
    read -n1 -s -r -p $'🔁 Press any key to return to main menu...'
}

# Status and Psiphon location count
check_status() {
    if [[ -x "/usr/bin/psiphon" ]] ; then
        psi_status="${GREEN}✓ Installed${RESET}"
    else
        psi_status="${RED}✗ Not Found${RESET}"
    fi
    [[ -x "$(command -v firejail)" ]] && fj_status="${GREEN}✓ Installed${RESET}" || fj_status="${RED}✗ Not Found${RESET}"
    # Count psiphon-* folders in $HOME and also in $HOME/psiphon (support both layouts)
    loc_count=$( (find "$HOME" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null; \
                  find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null) | wc -l )
