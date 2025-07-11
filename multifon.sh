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
echo -e "███╗   ███╗██╗   ██╗██╗  ████████╗██╗ ███████╗ ██████╗ ███╗   ██╗"
echo -e "████╗ ████║██║   ██║██║  ╚══██╔══╝██║ ██╔════╝██╔═══██╗████╗  ██║"
echo -e "██╔████╔██║██║   ██║██║     ██║   ██║ █████╗  ██║   ██║██╔██╗ ██║"
echo -e "██║╚██╔╝██║██║   ██║██║     ██║   ██║ ██╔══╝  ██║   ██║██║╚██╗██║"
echo -e "██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║ ██║     ╚██████╔╝██║ ╚████║"
echo -e "╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝ ╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
echo -e "                    ${WHITE}Multi Psiphon Manager${RESET}${CYAN}  | ${WHITE}Source: Psiphon SpherionOS ${RESET}"
echo ""
}


# status and location count

# Color codes
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

pause() {
    echo ""
    read -n1 -s -r -p $'\n🔁 Press any key to return to main menu...'
}

check_status() {
    if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
        psi_status="${GREEN}✓ Installed${RESET}"
    else
        psi_status="${RED}✗ Not Found${RESET}"
    fi
    [[ -x "$(command -v firejail)" ]] && fj_status="${GREEN}✓ Installed${RESET}" || fj_status="${RED}✗ Not Found${RESET}"
    loc_count=$(find "$HOME/psiphon/" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l)

    echo -e "${YELLOW}${BOLD}───────────────────────────────${RESET}"
    echo -e "${WHITE}${BOLD} Psiphon Multi-Manager Console ${RESET}"
    echo -e "${YELLOW}${BOLD}───────────────────────────────${RESET}"
    echo ""
    echo -e " System Check:"
    echo -e " - Psiphon installed: ${psi_status} ${CYAN}(/usr/bin/psiphon or /usr/bin/psiphon-tunnel-core-x86_64)${RESET}"
    echo -e " - Firejail installed: ${fj_status}"
    echo -e " - Number of configured Psiphon locations: ${MAGENTA}$loc_count${RESET}"
    echo -e " - Psiphon source: ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo -e "${YELLOW}${BOLD}───────────────────────────────${RESET}"
    echo ""
}

main_menu() {
    echo -e "${BLUE}Main Menu:${RESET}\n"
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail (Approx 5.5 MB)${RESET}"
    echo -e "${BLUE} 3) Create Psiphon Folder with Firejail${RESET}"
    echo -e "${BLUE} 4) Create Psiphon Folder without Firejail ${RED}#Not recommended for multi-location use${RESET}"
    echo -e "${BLUE} 5) Show Running Psiphon Instances${RESET}"
    echo -e "${BLUE} 6) Cleanup Options${RESET}"
    echo -e "\n${BLUE} 0) Exit${RESET}"
}

install_firejail() {
    echo -e "${BLUE}Installing Firejail...${RESET}"
    sudo apt update && sudo apt install -y firejail
    pause
}

create_folder() {
    local mode="$1"
    mkdir -p "$HOME/psiphon"
    if [[ "$mode" == "yes" ]]; then
        echo -e "${GREEN}Created Psiphon folder with Firejail in $HOME/psiphon${RESET}"
    else
        echo -e "${YELLOW}Created Psiphon folder without Firejail in $HOME/psiphon (Not recommended for multi-location use)${RESET}"
    fi
    pause
}

show_instances() {
    ps aux | grep -i psiphon | grep -v grep
    pause
}

cleanup_options() {
    echo -e "${MAGENTA}Cleanup Options:${RESET}"
    echo -e "1) Stop All Psiphon Instances"
    echo -e "2) Remove All Psiphon Folders"
    echo -e "3) Remove All Logs"
    echo -e "4) Remove Firejail-Only Data (isolated folders etc.)"
    echo -e "5) Full Reset (All Psiphon-related content)"
    echo -e "0) Back to Main Menu"
    read -p "Select an option [0-5]: " c_opt
    case "$c_opt" in
        1) pkill psiphon; echo -e "${GREEN}Stopped all Psiphon instances.${RESET}"; pause ;;
        2) rm -rf "$HOME/psiphon"; echo -e "${GREEN}Removed all Psiphon folders.${RESET}"; pause ;;
        3) rm -rf ~/.psiphon/logs; echo -e "${GREEN}Removed all Psiphon logs.${RESET}"; pause ;;
        4) rm -rf ~/.firejail; echo -e "${GREEN}Removed Firejail isolated folders.${RESET}"; pause ;;
        5) pkill psiphon; rm -rf "$HOME/psiphon" ~/.psiphon ~/.firejail /etc/psiphon /usr/bin/psiphon* /usr/bin/firejail; echo -e "${GREEN}Full reset done.${RESET}"; pause ;;
        0) ;;
        *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
    esac
}

install_psiphon_menu() {
    echo -e "${YELLOW}install_psiphon_menu is not implemented yet.${RESET}"
    pause
}

# Main loop
clear
check_status
while true; do
    main_menu
    echo ""
    read -p "Select an option [0-6]: " opt
    case "$opt" in
        1) install_psiphon_menu ;;
        2) install_firejail ;;
        3) create_folder yes ;;
        4) create_folder no ;;
        5) show_instances ;;
        6) cleanup_options ;;
        0) echo -e "${GREEN}Exiting...${RESET}"; exit 0 ;;
        *) echo -e "${RED}Invalid option, please try again.${RESET}"; pause ;;
    esac
done
