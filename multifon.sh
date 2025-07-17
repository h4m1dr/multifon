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
    loc_count=$(find "$HOME/psiphon/" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l)

    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    echo -e " System Check:"
    echo -e " - Psiphon installed: ${psi_status} ${CYAN}(/usr/bin/psiphon)${RESET}"
    echo -e " - Firejail installed: ${fj_status}"
    echo -e " - Number of configured Psiphon locations: ${MAGENTA}$loc_count${RESET}"
    echo -e " - Psiphon source: ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    echo ""
}


# Directories
PSIPHON_BASE_DIR="$HOME"
FIREJAIL_CONFIG_DIR="/etc/firejail"

# Main menu display
main_menu() {
    echo -e "${YELLOW}Main Menu:${RESET}"
    echo ""
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail ${YELLOW}(Approx 5.5 MB)${RESET}"
    echo -e "${BLUE} 3) Psiphon Folder Management${RESET}"
    echo -e "${BLUE} 4) Show Running Psiphon Instances${RESET}"
    echo -e "${BLUE} 5) Cleanup Options${RESET}"
    echo ""
    echo -e "${BLUE} 0) Exit${RESET}"
}


# 1) Psiphon Installation Menu
install_psiphon_menu() {
    local installed="No"
    if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
        installed="Yes"
    fi
    
    clear
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Psiphon Installation Menu:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Automatic Global Installation ${RED}(Recommended)${RESET}${YELLOW} (Approx 20 MB)${RESET}"
        echo -e "${BLUE} 2) Manual Installation ${RED}(Outdated Archive)${RESET}${YELLOW} (Approx 20 MB)${RESET}"
        echo -e "${BLUE} 3) Latest Binary Download ${YELLOW}(Approx 20 MB)${RESET}"
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



# 2) Install Firejail
install_firejail() {
    echo -e "${CYAN}Checking Firejail installation...${RESET}"
    
    if command -v firejail &> /dev/null; then
        echo -e "${GREEN}Firejail is already installed.${RESET}"
    else
        echo -e "${YELLOW}Installing Firejail...${RESET}"
        sudo apt update && sudo apt install -y firejail
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Firejail installed successfully.${RESET}"
        else
            echo -e "${RED}Failed to install Firejail.${RESET}"
        fi
    fi

    echo -e "${CYAN}Returning to main menu...${RESET}"
    sleep 2
}


# 3) Psiphon Folder Management
psiphon_folder_menu() {
    clear
    logo
    check_status
    echo -e "${YELLOW}Select how you want Psiphon to autostart:${RESET}"
    echo ""
    echo -e "${BLUE} 1) Creating Psiphon folders"
    echo -e "${BLUE} 2) nohup based autostart"
    echo -e "${BLUE} 3) systemd service based autostart"
    echo ""
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
    echo ""
    read -rp "Choose [0-3]: " boot_choice
    generate_start_script "$boot_choice"
}


# Creating Psiphon folders
Creating_Psiphon_folders() {
    echo -e "${CYAN}🔧 Creating Psiphon folders...${RESET}"

    echo -e "📍 Enter comma-separated country codes (e.g., at,ie,gb):"
    read -rp "➤ Country codes: " raw_countries
    IFS=',' read -ra countries <<< "$raw_countries"

    echo -e "📁 Optionally enter folder names for each country (comma-separated, e.g., myat,myie,mygb)."
    echo -e "ℹ️  If left blank or mismatched count, default names will be used (psiphon-<cc>)"
    read -rp "➤ Folder names: " raw_names
    IFS=',' read -ra names <<< "$raw_names"

    used_ports=()
    http_port=8081
    socks_port=1081

    for i in "${!countries[@]}"; do
        cc="${countries[i]}"
        cc_trimmed=$(echo "$cc" | xargs)
        name="${names[i]}"
        [[ -z "$name" ]] && name="psiphon-${cc_trimmed}"

        dir_path="$PSIPHON_BASE_DIR/$name"
        mkdir -p "$dir_path"
        cp "$PSIPHON_BASE_DIR/psiphon-tunnel-core" "$dir_path/psiphon-tunnel-core-x86_64"
        chmod +x "$dir_path/psiphon-tunnel-core-x86_64"

        # Find available ports
        while ss -tuln | grep -q ":$http_port "; do ((http_port++)); done
        while ss -tuln | grep -q ":$socks_port "; do ((socks_port++)); done

        # Create config
        cat > "$dir_path/config.json" <<EOF
{
  "socksProxyPort": $socks_port,
  "httpProxyPort": $http_port
}
EOF

        echo -e "${GREEN}✔ Created $name [Country: $cc_trimmed | HTTP: $http_port | SOCKS: $socks_port]${RESET}"

        used_ports+=("$http_port" "$socks_port")
        ((http_port++))
        ((socks_port++))
    done
}


# Show Psiphon instances
show_running_psiphon() {
    echo -e "${YELLOW}Running Psiphon Instances:${RESET}"
    ps aux | grep psiphon | grep -v grep
    echo -e "${YELLOW}🔁 Press any key to return to main menu...${RESET}"
    read -n 1 -s
}

# Cleanup menu
cleanup_menu() {
    clear
    logo
    check_status
    echo -e "${YELLOW}Cleanup Options:${RESET}"
    echo ""
    echo -e "${BLUE} 1) Remove All Psiphon Folders${RESET}"
    echo -e "${BLUE} 2) Remove Firejail${RESET}"
    echo ""
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
    echo ""
    read -rp "Select an option [0-2]: " clean_option
    case $clean_option in
        1) rm -rf $HOME/psiphon-* && echo -e "${GREEN}All Psiphon folders removed.${RESET}" ;;
        2) sudo apt purge firejail -y && echo -e "${GREEN}Firejail removed.${RESET}" ;;
        0) return ;;
        *) echo -e "${RED}Invalid option.${RESET}" ;;
    esac
}

# Main loop
while true; do
    clear
    logo
    check_status
    main_menu
    echo ""
    read -rp "Select an option [0-5]: " option
    case $option in
        1) install_psiphon_menu ;;
        2) install_firejail ;;
        3) psiphon_folder_menu ;;
        4) show_running_psiphon ;;
        5) cleanup_menu ;;
        0) echo -e "${CYAN}Exiting...${RESET}"; exit ;;
        *) echo -e "${RED}Invalid option. Please try again.${RESET}" ;;
    esac
done
