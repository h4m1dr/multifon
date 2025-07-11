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

# Pause function to return to menu
pause() {
    echo ""
    read -n1 -s -r -p $'🔁 Press any key to return to menu...'
}

# Psiphon Installation submenu
install_psiphon() {
    while true; do
        clear
        # لوگو اینجا نیست چون خودت داری
        echo -e "${YELLOW}${BOLD}╭───────────────────────────────╮${RESET}"
        echo -e "${YELLOW}${BOLD}│      ${WHITE}Psiphon Installation Menu${YELLOW}      │${RESET}"
        echo -e "${YELLOW}${BOLD}╰───────────────────────────────╯${RESET}"

        if [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
            echo -e "${GREEN}Psiphon is installed.${RESET}"
        else
            echo -e "${RED}Psiphon is NOT installed.${RESET}"
        fi

        echo ""
        echo -e " ${CYAN}[1]${RESET} Automatic Global Installation (plinstaller2)"
        echo -e " ${CYAN}[2]${RESET} Manual Installation (Archive)"
        echo -e " ${CYAN}[3]${RESET} Update to Latest Version"
        echo -e " ${CYAN}[4]${RESET} Uninstall Psiphon"
        echo -e " ${CYAN}[5]${RESET} Delete Psiphon Files Only (without uninstall)"
        echo -e " ${CYAN}[6]${RESET} Back to Main Menu"
        echo ""

        read -p $'\e[1;33mSelect an option [1-6]: \e[0m' ps_opt

        case "$ps_opt" in
            1)
                echo -e "${BLUE}Starting automatic installation...${RESET}"
                # دستور نصب اتوماتیک
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
                echo "(Placeholder) Update process..."
                pause
                ;;
            4)
                echo -e "${RED}Uninstalling Psiphon completely...${RESET}"
                echo "(Placeholder) Uninstall Psiphon..."
                pause
                ;;
            5)
                echo -e "${YELLOW}Deleting only Psiphon files...${RESET}"
                echo "(Placeholder) Delete files only..."
                pause
                ;;
            6)
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid option. Try again.${RESET}"
                pause
                ;;
        esac
    done
}

# Start main loop
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
