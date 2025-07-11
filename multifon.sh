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


install_psiphon_menu() {
    local installed="No"
    if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
        installed="Yes"
    fi

    while true; do
        clear
        echo -e "${CYAN}╭───────────────────────────────╮${RESET}"
        echo -e "${CYAN}│       Psiphon Installation Menu       │${RESET}"
        echo -e "${CYAN}╰───────────────────────────────╯${RESET}"
        echo ""
        echo -e " • Psiphon:     ${GREEN}✓ Installed${RESET}  /usr/bin/psiphon-tunnel-core-x86_64"
        echo ""
        echo -e " • Source:      ${YELLOW}https://github.com/SpherionOS/PsiphonLinux${RESET}"
        echo ""

        echo -e "${BLUE} 1) Automatic Global Installation ${RED}(Recommended)${RESET}${YELLOW} (Approx 20 MB)${RESET}"
        echo -e "${BLUE} 2) Manual Installation ${RED}(Outdated Archive)${RESET}${YELLOW} (Approx 20 MB)${RESET}"
        echo -e "${BLUE} 3) Latest Binary Download ${RED}(Approx 20 MB)${RESET}"
        echo ""
        echo -e "${BLUE} 4) Uninstall Psiphon ${RESET}(using pluninstaller)"
        echo -e "${BLUE} 5) Remove Psiphon Core Files ${RESET}(manual wipe)"
        echo -e "${BLUE} 6) Remove Only Extra Installer Files ${RESET}(safe wipe)"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"

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
                    rm -f "$temp_file"
                else
                    echo -e "${BLUE}Updating to latest version...${RESET}"
                    sudo mv "$temp_file" /usr/bin/psiphon-tunnel-core-x86_64
                    sudo chmod +x /usr/bin/psiphon-tunnel-core-x86_64
                fi
                pause
                ;;
            4)
                if ! [[ -x "/usr/bin/psiphon" ]] && ! [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
                    echo -e "${YELLOW}Psiphon is not installed.${RESET}"
                else
                    echo -e "${RED}Uninstalling Psiphon...${RESET}"
                    wget -q https://raw.githubusercontent.com/SpherionOS/PsiphonLinux/main/pluninstaller && \
                    sudo bash pluninstaller && rm -f pluninstaller
                fi
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


create_folder_with_firejail() {
    mkdir -p "$HOME/psiphon"
    echo -e "${GREEN}Created Psiphon folder with Firejail in $HOME/psiphon${RESET}"
    pause
}

create_folder_without_firejail() {
    mkdir -p "$HOME/psiphon"
    echo -e "${YELLOW}Created Psiphon folder without Firejail in $HOME/psiphon (Not recommended for multi-location use)${RESET}"
    pause
}

show_running_psiphon() {
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
        1)
            pkill psiphon
            echo -e "${GREEN}Stopped all Psiphon instances.${RESET}"
            pause
            ;;
        2)
            rm -rf "$HOME/psiphon"
            echo -e "${GREEN}Removed all Psiphon folders.${RESET}"
            pause
            ;;
        3)
            rm -rf ~/.psiphon/logs
            echo -e "${GREEN}Removed all Psiphon logs.${RESET}"
            pause
            ;;
        4)
            rm -rf ~/.firejail
            echo -e "${GREEN}Removed Firejail isolated folders.${RESET}"
            pause
            ;;
        5)
            pkill psiphon
            rm -rf "$HOME/psiphon" ~/.psiphon ~/.firejail /etc/psiphon /usr/bin/psiphon* /usr/bin/firejail
            echo -e "${GREEN}Full reset done.${RESET}"
            pause
            ;;
        0)
            ;;
        *)
            echo -e "${RED}Invalid option.${RESET}"
            pause
            ;;
    esac
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
