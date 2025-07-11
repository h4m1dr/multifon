#!/bin/bash

# رنگ‌ها
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

# لوگوی مولتی سایفون (الهام گرفته از GamingVPN)
logo() {
clear
echo -e "${CYAN}${BOLD}"
echo -e "███╗   ███╗ ██████╗ ██╗   ██╗██╗   ████████╗██╗ ███████╗ ██████╗ ███╗   ██╗"
echo -e "████╗ ████║██╔═══██╗██║   ██║██║   ╚══██╔══╝██║ ██╔════╝██╔═══██╗████╗  ██║"
echo -e "██╔████╔██║██║   ██║██║   ██║██║      ██║   ██║ █████╗  ██║   ██║██╔██╗ ██║"
echo -e "██║╚██╔╝██║██║   ██║██║   ██║██║      ██║   ██║ ██╔══╝  ██║   ██║██║╚██╗██║"
echo -e "██║ ╚═╝ ██║╚██████╔╝╚██████╔╝███████╗ ██║   ██║ ██║     ╚██████╔╝██║ ╚████║"
echo -e "╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝ ╚═╝   ╚═╝ ╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
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

# main menu
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

# pause helper
pause() {
    echo ""
    read -n1 -s -r -p $'🔁 Press any key to return to menu...'
}

# Psiphon installation menu
install_psiphon() {
    while true; do
        clear
        echo -e "┌───────────────────────────────────────────────┐"
        echo -e "│         ${BOLD}Psiphon Installation Menu${RESET}         │"
        echo -e "└───────────────────────────────────────────────┘"
        echo ""
        if [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
            echo -e "Psiphon is ${GREEN}installed${RESET}."
        else
            echo -e "Psiphon is ${RED}not installed${RESET}."
        fi
        echo ""
        echo -e "  1) Automatic Global Installation (plinstaller2)"
        echo -e "  2) Manual Installation (Archive)"
        echo -e "  3) Update to Latest Version"
        echo -e "  4) Uninstall Psiphon"
        echo -e "  5) Delete Psiphon Files Only (without uninstall)"
        echo -e "  6) Back to Main Menu"
        echo ""
        read -p "Select an option [1-6]: " ps_opt

        case "$ps_opt" in
            1)
                echo -e "${BLUE}Starting automatic installation...${RESET}"
                echo "(Placeholder) Running plinstaller2 script..."
                pause
                ;;
            2)
                echo -e "${BLUE}Starting manual installation...${RESET}"
                echo "(Placeholder) Manual install from archive..."
                pause
                ;;
            3)
                echo -e "${BLUE}Updating Psiphon to latest version...${RESET}"
                echo "(Placeholder) Running update..."
                pause
                ;;
            4)
                echo -e "${RED}Uninstalling Psiphon...${RESET}"
                echo "(Placeholder) Removing binary from /usr/bin..."
                pause
                ;;
            5)
                echo -e "${YELLOW}Deleting Psiphon files only...${RESET}"
                echo "(Placeholder) Deleting psiphon-tunnel-core-x86_64..."
                pause
                ;;
            6)
                break
                ;;
            *)
                echo -e "${RED}Invalid option, please try again.${RESET}"
                pause
                ;;
        esac
    done
}

# Placeholder functions
install_firejail() {
    echo -e "${BLUE}Installing Firejail...${RESET}"
    pause
}

create_folder() {
    if [[ "$1" == "yes" ]]; then
        echo -e "${GREEN}Creating folder with Firejail...${RESET}"
    else
        echo -e "${YELLOW}Creating folder WITHOUT Firejail... (Not recommended)${RESET}"
    fi
    pause
}

show_instances() {
    echo -e "${CYAN}Listing running Psiphon instances (simulated)...${RESET}"
    pause
}

cleanup_options() {
    echo -e "${RED}Cleanup Options (folders / firejail configs)...${RESET}"
    pause
}

# Main loop
while true; do
    logo
    check_status
    main_menu
    read -p $'\e[1;33mSelect an option [0-6]: \e[0m' opt
    case "$opt" in
        1) install_psiphon ;;
        2) install_firejail ;;
        3) create_folder yes ;;
        4) create_folder no ;;
        5) show_instances ;;
        6) cleanup_options ;;
        0) echo -e "${GREEN}Exiting Multi Psiphon...${RESET}"; exit 0 ;;
        *) echo -e "${RED}❌ Invalid option. Please try again.${RESET}"; pause ;;
    esac
done
