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



# Helper: pause for input

pause() {
    echo ""
    read -n1 -s -r -p $'🔁 Press any key to return to main menu...'
}

# Status and Psiphon location count

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


# Directories
PSIPHON_BASE_DIR="$HOME"
FIREJAIL_CONFIG_DIR="/etc/firejail"

# Main menu display
main_menu() {
    echo -e "${BLUE}Main Menu:${RESET}"
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail (Approx 5.5 MB)${RESET}"
    echo -e "${BLUE} 3) Psiphon Folder Management${RESET}"
    echo -e "${BLUE} 4) Show Running Psiphon Instances${RESET}"
    echo -e "${BLUE} 5) Cleanup Options${RESET}"
    echo -e "${BLUE} 0) Exit${RESET}"
}


# 1) Psiphon Installation Menu
install_psiphon_menu() {
    local installed="No"
    if [[ -x "/usr/bin/psiphon" ]] || [[ -f "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
        installed="Yes"
    fi

    while true; do
        clear
        echo -e "${CYAN}╭───────────────────────────────╮${RESET}"
        echo -e "${CYAN}│  Psiphon Installation Menu    │${RESET}"
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
    echo -e "${YELLOW}Select how you want Psiphon to autostart:${RESET}"
    echo -e "${BLUE} 1) Creating Psiphon folders"
    echo -e "${BLUE} 2) nohup based autostart"
    echo -e "${BLUE} 3) systemd service based autostart"
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
    read -rp "Choose [1-2]: " boot_choice
    generate_start_script "$boot_choice"
}

# 
psiphon_folder_menu1() {
    echo -e "${CYAN}Creating Psiphon folders...${RESET}"
    read -rp "Enter space-separated country codes (e.g., gb fr us): " countries
    for country in $countries; do
        mkdir -p "$PSIPHON_BASE_DIR/psiphon-$country"
        cp "$PSIPHON_BASE_DIR/psiphon-tunnel-core" "$PSIPHON_BASE_DIR/psiphon-$country/psiphon-tunnel-core-x86_64"
        chmod +x "$PSIPHON_BASE_DIR/psiphon-$country/psiphon-tunnel-core-x86_64"
        echo -e "${GREEN}Created and prepared folder for $country.${RESET}"
    done
}

generate_start_script() {
    boot_choice="$1"
    cat > "$PSIPHON_BASE_DIR/start-psiphons.sh" <<EOF
#!/bin/bash

for dir in gb fr at ch; do
    echo "Starting Psiphon: \$dir"
    cd ~/psiphon-\$dir || continue

    if [ ! -f psiphon-tunnel-core-x86_64 ] && [ -f psiphon-tunnel-core ]; then
        mv psiphon-tunnel-core psiphon-tunnel-core-x86_64
        chmod +x psiphon-tunnel-core-x86_64
    fi

    nohup firejail --private=. ./psiphon-tunnel-core-x86_64 -config config.json > log.txt 2>&1 &
done
EOF
    chmod +x "$PSIPHON_BASE_DIR/start-psiphons.sh"

    if [[ "$boot_choice" == "2" ]]; then
        sudo tee /etc/systemd/system/psiphon-autostart.service > /dev/null <<EOL
[Unit]
Description=Auto start Psiphon via start-psiphons.sh
After=network.target

[Service]
ExecStart=$PSIPHON_BASE_DIR/start-psiphons.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL
        sudo systemctl daemon-reexec
        sudo systemctl enable psiphon-autostart
        echo -e "${GREEN}Systemd autostart enabled.${RESET}"
    else
        echo -e "${GREEN}Nohup-based autostart script created. Add it to your .bashrc or crontab if needed.${RESET}"
    fi
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
    echo -e "${CYAN}Cleanup Options:${RESET}"
    echo -e "${BLUE} 1) Remove All Psiphon Folders${RESET}"
    echo -e "${BLUE} 2) Remove Firejail${RESET}"
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
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
