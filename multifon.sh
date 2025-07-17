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
    read -n1 -s -r -p $'\n🔁 Press any key to return to main menu...'
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
# Main menu display
main_menu() {
    echo -e "${BLUE}Main Menu:${RESET}\n"
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail (Approx 5.5 MB)${RESET}"
    echo -e "${BLUE} 3) Psiphon Folder Management${RESET}"
    echo -e "${BLUE} 4) Show Running Psiphon Instances${RESET}"
    echo -e "${BLUE} 5) Cleanup Options${RESET}"
    echo -e "\n${BLUE} 0) Exit${RESET}"
}

# Psiphon folder management submenu
psiphon_folder_menu() {
    echo -e "${CYAN}\nPsiphon Folder Management:${RESET}"
    echo -e "${BLUE} 1) Create Psiphon Folders for Multiple Locations${RESET}"
    echo -e "${BLUE} 2) Link Firejail to Psiphon and Set Autostart${RESET}"
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
    read -rp "\nSelect an option [0-2]: " sub_option
    case $sub_option in
        1) create_psiphon_locations_with_firejail ;;
        2) link_firejail_autostart_prompt ;;
        0) return ;;
        *) echo -e "${RED}Invalid option.${RESET}" ;;
    esac
}

# Psiphon installation function
install_psiphon_menu() {
    echo -e "${GREEN}Installing Psiphon...${RESET}"
    curl -s -O https://raw.githubusercontent.com/SpherionOS/PsiphonLinux/main/plinstaller2.sh
    chmod +x plinstaller2.sh
    ./plinstaller2.sh
}

# Install Firejail
install_firejail() {
    echo -e "${GREEN}Installing Firejail...${RESET}"
    sudo apt update && sudo apt install firejail -y
    echo -e "${GREEN}Firejail installation completed.${RESET}"
}

# Create Psiphon folders with Firejail
create_psiphon_locations_with_firejail() {
    echo -e "${CYAN}Creating Psiphon folders...${RESET}"
    read -rp "Enter space-separated country codes (e.g., gb fr us): " countries
    for country in $countries; do
        mkdir -p "$PSIPHON_BASE_DIR/psiphon-$country"
        cp "$PSIPHON_BASE_DIR/psiphon-tunnel-core" "$PSIPHON_BASE_DIR/psiphon-$country/psiphon-tunnel-core-x86_64"
        chmod +x "$PSIPHON_BASE_DIR/psiphon-$country/psiphon-tunnel-core-x86_64"
        echo -e "${GREEN}Created and prepared folder for $country.${RESET}"
    done
}

# Ask and create startup method
link_firejail_autostart_prompt() {
    echo -e "${YELLOW}Select how you want Psiphon to autostart:${RESET}"
    echo -e "${BLUE} 1) nohup based autostart"
    echo -e "${BLUE} 2) systemd service based autostart"
    read -rp "\nChoose [1-2]: " boot_choice
    generate_start_script "$boot_choice"
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
    echo -e "\n${YELLOW}🔁 Press any key to return to main menu...${RESET}"
    read -n 1 -s
}

# Cleanup menu
cleanup_menu() {
    echo -e "${CYAN}\nCleanup Options:${RESET}"
    echo -e "${BLUE} 1) Remove All Psiphon Folders${RESET}"
    echo -e "${BLUE} 2) Remove Firejail${RESET}"
    echo -e "${BLUE} 0) Back to Main Menu${RESET}"
    read -rp "\nSelect an option [0-2]: " clean_option
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
    read -p "Select an option [0-5]: " opt
    case "$opt" in
        1) install_psiphon_menu ;;
        2) install_firejail ;;
        3) create_psiphon_folder_menu ;;
        4) Psiphon_status ;;
        5) cleanup_options ;;
        0) echo -e "${GREEN}Exiting...${RESET}"; exit 0 ;;
        *) echo -e "${RED}Invalid option, please try again.${RESET}"; pause ;;
    esac

