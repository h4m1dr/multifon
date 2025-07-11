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
    echo -e "Main Menu:\n"
    echo -e " 1) Psiphon Installation Menu     #Source: SpherionOS"
    echo -e " 2) Install Firejail"
    echo -e " 3) Create Psiphon Folder with Firejail"
    echo -e " 4) Create Psiphon Folder without Firejail    #Not recommended for multi-location use"
    echo -e " 5) Show Running Psiphon Instances"
    echo -e " 6) Cleanup Options"
    echo -e "\n 0) Exit"
}

install_psiphon() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}Psiphon Installation Menu${RESET}"
        echo -e "Source: https://github.com/SpherionOS/PsiphonLinux"

        if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
            echo -e "Installed: ${GREEN}Yes${RESET}"
        else
            echo -e "Installed: ${RED}No${RESET}"
        fi

        echo ""
        echo -e " 1) Automatic Global Installation (Recommended)"
        echo -e " 2) Manual Installation (Outdated Archive)"
        echo -e " 3) Latest Binary Download"
        echo -e ""
        echo -e " 4) Uninstall Psiphon (using pluninstaller)"
        echo -e " 5) Remove Psiphon Core Files (manual wipe)"
        echo -e " 6) Remove Only Extra Installer Files (safe wipe)"
        echo -e "\n 0) Back to Main Menu"
        echo ""

        read -p "Select an option [0-6]: " ps_opt
        case "$ps_opt" in
            1)
                if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
                    echo -e "${YELLOW}Psiphon is already installed. Skipping installation.${RESET}"
                else
                    if [[ -f ./plinstaller2 ]]; then
                        echo -e "${BLUE}Found existing plinstaller2, using local copy...${RESET}"
                        sudo bash plinstaller2
                    else
                        echo -e "${BLUE}Downloading and running automatic installer...${RESET}"
                        wget -q https://raw.githubusercontent.com/SpherionOS/PsiphonLinux/main/plinstaller2 && \
                        sudo bash plinstaller2 && rm -f plinstaller2
                    fi
                fi
                pause
                ;;
            2)
                if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
                    echo -e "${YELLOW}Psiphon is already installed. Manual install skipped.${RESET}"
                else
                    echo -e "${BLUE}Running manual installation...${RESET}"
                    git clone https://github.com/SpherionOS/PsiphonLinux.git ~/PsiphonLinux && \
                    cd ~/PsiphonLinux/archive && \
                    chmod +x psiphon-tunnel-core-x86_64 psiphon.sh
                fi
                pause
                ;;
            3)
                latest_url="https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/linux/psiphon-tunnel-core-x86_64"
                temp_file="/tmp/psiphon-latest"
                wget -q -O "$temp_file" "$latest_url"
                if cmp -s "$temp_file" "/usr/bin/psiphon-tunnel-core-x86_64"; then
                    echo -e "${GREEN}Already up to date.${RESET}"
                else
                    echo -e "${BLUE}Updating to latest version...${RESET}"
                    sudo mv "$temp_file" /usr/bin/psiphon-tunnel-core-x86_64
                    sudo chmod +x /usr/bin/psiphon-tunnel-core-x86_64
                fi
                pause
                ;;
            4)
                echo -e "${RED}Uninstalling Psiphon...${RESET}"
                wget -q https://raw.githubusercontent.com/SpherionOS/PsiphonLinux/main/pluninstaller && \
                sudo bash pluninstaller && rm -f pluninstaller
                pause
                ;;
            5)
                echo -e "${RED}Removing core files...${RESET}"
                sudo find /usr/bin /etc "$HOME" -type f -name "psiphon*" -exec rm -f {} +
                pause
                ;;
            6)
                echo -e "${YELLOW}Removing only extra installer files...${RESET}"
                sudo find /usr/bin /etc "$HOME" -type f \( -name "plinstaller2" -o -name "pluninstaller" \) -exec rm -f {} +
                pause
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Invalid option, please try again.${RESET}"
                pause
                ;;
        esac
    done
}


install_firejail() {
    echo -e "${BLUE}Installing Firejail...${RESET}"
    sudo apt update && sudo apt install -y firejail
    pause
}

create_folder() {
    if [[ "$1" == "yes" ]]; then
        echo -e "${GREEN}Creating folder with Firejail...${RESET}"
    else
        echo -e "${YELLOW}Creating folder WITHOUT Firejail...${RESET}"
    fi
    pause
}

show_instances() {
    echo -e "${CYAN}Showing running Psiphon instances (simulated)...${RESET}"
    pause
}

cleanup_options() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}Cleanup Options${RESET}"
        echo -e "\n 1) Stop All Psiphon Instances"
        echo -e " 2) Remove All Psiphon Folders"
        echo -e " 3) Remove All Logs"
        echo -e " 4) Remove Firejail-Only Data (isolated folders etc.)"
        echo -e "\n 5) Full Reset (All Psiphon-related content)"
        echo -e "\n 0) Back to Main Menu"
        echo ""

        read -p "Select an option [0-5]: " clean_opt
        case "$clean_opt" in
            1)
                echo -e "${BLUE}Stopping all Psiphon instances...${RESET}"
                pkill -f psiphon-tunnel-core-x86_64
                pause
                ;;
            2)
                echo -e "${BLUE}Removing all Psiphon folders...${RESET}"
                rm -rf "$HOME/psiphon/"
                pause
                ;;
            3)
                echo -e "${BLUE}Removing all logs...${RESET}"
                find "$HOME/psiphon/" -type f -name "*.log" -delete
                pause
                ;;
            4)
                echo -e "${BLUE}Removing firejail-only data...${RESET}"
                rm -rf "$HOME/.config/firejail"
                pause
                ;;
            5)
                echo -e "${RED}Performing full reset...${RESET}"
                sudo rm -f /usr/bin/psiphon-tunnel-core-x86_64
                sudo rm -rf /etc/psiphon
                rm -rf "$HOME/psiphon/"
                rm -rf "$HOME/.config/firejail"
                pause
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Invalid option, please try again.${RESET}"
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
    echo ""
    read -p "Select an option [0-6]: " opt
    case "$opt" in
        1) install_psiphon ;;
        2) install_firejail ;;
        3) create_folder yes ;;
        4) create_folder no ;;
        5) show_instances ;;
        6) cleanup_options ;;
        0) echo -e "${GREEN}Exiting...${RESET}"; exit 0 ;;
        *) echo -e "${RED}Invalid option, please try again.${RESET}"; pause ;;
    esac
done
