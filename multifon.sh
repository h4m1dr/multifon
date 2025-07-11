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

# Pause function
pause() {
    echo ""
    read -n1 -s -r -p $'\n🔁 Press any key to return to menu...'
}

# System Check
check_status() {
    [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]] && psi_status="Yes (/usr/bin/psiphon-tunnel-core-x86_64)" || psi_status="No"
    [[ -x "$(command -v firejail)" ]] && fj_status="Yes" || fj_status="No"
    loc_count=$(find "$HOME/psiphon/" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l)

    echo -e "\n───────────────────────────────"
    echo -e " Psiphon Multi-Manager Console"
    echo -e "───────────────────────────────"
    echo -e "\nSystem Check:"
    echo -e "- Psiphon installed: ${psi_status}"
    echo -e "- Firejail installed: ${fj_status}"
    echo -e "- Number of configured Psiphon locations: ${loc_count}"
    echo -e "- Psiphon source: https://github.com/SpherionOS/PsiphonLinux"
    echo -e "───────────────────────────────\n"
}

# Psiphon Installation Menu
install_psiphon() {
    while true; do
        clear
        echo "Psiphon Installation Menu"
        echo "Source: https://github.com/SpherionOS/PsiphonLinux"
        if [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
            echo "Installed: Yes (/usr/bin/psiphon-tunnel-core-x86_64)"
        else
            echo "Installed: No"
        fi
        echo ""
        echo "1) Automatic Global Installation (Recommended)"
        echo "2) Manual Installation (Outdated Archive)"
        echo "3) Latest Binary Download"
        echo ""
        echo "4) Uninstall Psiphon (using pluninstaller)"
        echo "5) Remove Psiphon Core Files (manual wipe)"
        echo ""
        echo "0) Back to Main Menu"
        echo ""
        read -p "Select an option [0-5]: " ps_opt

        case "$ps_opt" in
            1)
                echo "Running plinstaller2..."
                pause ;;
            2)
                echo "Manual installation placeholder..."
                pause ;;
            3)
                echo "Downloading latest binary..."
                pause ;;
            4)
                echo "Uninstalling Psiphon..."
                pause ;;
            5)
                echo "Removing Psiphon files..."
                pause ;;
            0)
                break ;;
            *)
                echo "Invalid option, please try again."
                pause ;;
        esac
    done
}

# Main Menu
main_menu() {
    echo "Main Menu:"
    echo ""
    echo "1) Psiphon Installation Menu     #Source: SpherionOS"
    echo "2) Install Firejail"
    echo "3) Create Psiphon Folder with Firejail"
    echo "4) Create Psiphon Folder without Firejail    #Not recommended for multi-location use"
    echo "5) Show Running Psiphon Instances"
    echo "6) Cleanup Options"
    echo ""
    echo "0) Exit"
    echo ""
}

# Placeholder functions
install_firejail() { echo "Installing Firejail..."; pause; }
create_folder() {
    if [[ "$1" == "yes" ]]; then
        echo "Creating folder with Firejail..."
    else
        echo "Creating folder WITHOUT Firejail... (Not recommended)"
    fi
    pause
}
show_instances() { echo "Listing running Psiphon instances..."; pause; }
cleanup_options() {
    echo "Cleanup Options:"
    echo "1) Stop All Psiphon Instances"
    echo "2) Remove All Psiphon Folders"
    echo "3) Remove All Logs"
    echo "4) Remove Firejail-Only Data (isolated folders etc.)"
    echo "5) Full Reset (All Psiphon-related content)"
    echo ""
    echo "0) Back to Main Menu"
    pause
}

# Main Loop
while true; do
    clear
    logo
    check_status
    main_menu
    read -p "Select an option [0-6]: " opt
    case "$opt" in
        1) install_psiphon ;;
        2) install_firejail ;;
        3) create_folder yes ;;
        4) create_folder no ;;
        5) show_instances ;;
        6) cleanup_options ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option."; pause ;;
    esac
    clear
done