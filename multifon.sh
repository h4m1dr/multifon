printf '#!/bin/bash
set -e
cd %q || exit 1
if [ ! -f ./config.json ]; then echo "ERROR: config.json missing in %q" >&2; exit 10; fi
if [ ! -x ./psiphon-tunnel-core-x86_64 ]; then
  if [ -f ./psiphon-tunnel-core-x86_64 ]; then chmod +x ./psiphon-tunnel-core-x86_64; else echo "ERROR: psiphon-tunnel-core-x86_64 missing in %q" >&2; exit 11; fi
fi
exec firejail --quiet --noprofile --private=. --whitelist=. --env=HOME=. --dns=1.1.1.1 --dns=8.8.8.8 ./psiphon-tunnel-core-x86_64 -config ./config.json
' "$dir_path" "$dir_path" "$dir_path" > "$dir_path/start.sh"#!/bin/bash

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
    read -n1 -s -r -p $'🔁 Press any key to continue...'
}

# Status and Psiphon location count
check_status() {
    if [[ -x "/usr/bin/psiphon" ]] ; then
        psi_status="${GREEN}✓ Installed${RESET}"
    else
        psi_status="${RED}✗ Not Found${RESET}"
    fi
    [[ -x "$(command -v firejail)" ]] && fj_status="${GREEN}✓ Installed${RESET}" || fj_status="${RED}✗ Not Found${RESET}"
    loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )

    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    echo -e " System Check:"
    echo -e " - Psiphon installed: ${psi_status} ${CYAN}(/usr/bin/psiphon)${RESET}"
    echo -e " - Firejail installed: ${fj_status}"
    echo -e " - Number of configured Psiphon locations: ${MAGENTA}$loc_count${RESET}"
    echo -e " - Psiphon source: ${BLUE}https://github.com/SpherionOS/PsiphonLinux${RESET}"
    echo -e "${YELLOW}${BOLD}─────────────────────────────────────────────────────────────────────────────────────${RESET}"
    info_write_system
    echo ""
}

# Directories
PSIPHON_BASE_DIR="$HOME"
FIREJAIL_CONFIG_DIR="/etc/firejail"

# Persistent port registry (to avoid collisions across runs)
PORT_REG_FILE="$PSIPHON_BASE_DIR/psiphon/.allocated_ports"
port_registry_init() {
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
    [ -f "$PORT_REG_FILE" ] || : > "$PORT_REG_FILE"
}
port_registry_used_ports() {
    # prints list of ports (one per line) from registry
    awk '{print $2"
"$3}' "$PORT_REG_FILE" 2>/dev/null | awk 'NF'
}
port_registry_set_entry() {
    # usage: port_registry_set_entry <name> <http_port> <socks_port>
    local name="$1" http="$2" socks="$3"
    (
        # lock registry file during update
        flock -w 3 9 || { echo "${YELLOW}Port registry busy, skipping write for $name${RESET}"; exit 0; }
        tmp=$(mktemp)
        grep -v "^${name} " "$PORT_REG_FILE" 2>/dev/null > "$tmp" || true
        printf '%s %s %s
' "$name" "$http" "$socks" >> "$tmp"
        mv "$tmp" "$PORT_REG_FILE"
    ) 9>>"$PORT_REG_FILE"
}

# Helper: check if a port is in use (ss/netstat fallback)
port_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":$1 "
    else
        netstat -tuln 2>/dev/null | grep -q ":$1 "
    fi
}

# Helper: next free port within a range (avoids already-picked ports too)
next_free_port_in_range() {
    local start="$1" end="$2" p
    for ((p=start; p<=end; p++)); do
        if ! port_in_use "$p" && ! [[ " ${used_ports[*]} " == *" $p "* ]]; then
            echo "$p"; return 0
        fi
    done
    return 1
}

# Helper: next free port from a starting point upward (fallback)
next_free_port_any() {
    local p="$1"
    while true; do
        if ! port_in_use "$p" && ! [[ " ${used_ports[*]} " == *" $p "* ]]; then
            echo "$p"; return 0
        fi
        ((p++))
    done
}

# Helper: collect ports from existing configs so we never reuse them
collect_existing_ports() {
    local cfg hp sp
    while IFS= read -r cfg; do
        if command -v jq >/dev/null 2>&1; then
            hp=$(jq -r '.LocalHttpProxyPort // empty' "$cfg")
            sp=$(jq -r '.LocalSocksProxyPort // empty' "$cfg")
        else
            hp=$(grep -oE '"LocalHttpProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
            sp=$(grep -oE '"LocalSocksProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
        fi
        [[ -n "$hp" ]] && used_ports+=("$hp")
        [[ -n "$sp" ]] && used_ports+=("$sp")
    done < <( find "$HOME/psiphon" -maxdepth 2 -type f -name 'config.json' 2>/dev/null \
              | grep -E '/psiphon-[^/]+/config\.json$' | sort -u )
}

# Main menu display
main_menu() {
    echo -e "${YELLOW}Main Menu:${RESET}"
    echo ""
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail ${YELLOW}(Approx 5.5 MB)${RESET}"
echo ""
    echo -e "${BLUE} 3) Psiphon Folder Management${RESET}"
    echo -e "${BLUE} 4) Cleanup Options${RESET}"
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

    info_write_system
    echo -e "${CYAN}Returning to main menu...${RESET}"
    sleep 2
}

# 3) Psiphon Folder Management
psiphon_folder_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Select how you want Psiphon to autostart:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Create Psiphon folders ${WHITE}(with Firejail)${RESET}"
        echo -e "${BLUE} 2) Create Psiphon folders ${WHITE}(no Firejail - under repair)${RESET}"
        echo -e "${BLUE} 3) Check Psiphon status (all locations)${RESET}"
        echo -e "${BLUE} 4) Start all Psiphon locations${RESET}"
        echo -e "${BLUE} 5) Stop all Psiphon locations${RESET}"
        echo -e "${BLUE} 6) Restart all Psiphon locations${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-6]: " psiphon_folder
        case $psiphon_folder in
            1)
                Creating_Psiphon_folders
                ;;
            2)
                Creating_Psiphon_folders_no_firejail
                ;;
            3)
                check_all_psiphon
                ;;
            4)
                start_all_psiphon
                ;;
            5)
                stop_all_psiphon
                ;;
            6)
                restart_all_psiphon
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}Invalid option.${RESET}"; pause
                ;;
        esac
    done
}


# Info file to track locations/ports and paths
INFO_FILE="$PSIPHON_BASE_DIR/psiphon/INFO.txt"
info_write() {
    local name="$1" cc="$2" dir="$3" http="$4" socks="$5"
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
    [ -f "$INFO_FILE" ] || : > "$INFO_FILE"
    local bin="$dir/psiphon-tunnel-core-x86_64"
    local start="$dir/start.sh"
    local start_all="$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
    local files
    files=$(ls -1 "$dir" 2>/dev/null | sed 's/^/  - /')
    (
        flock -w 3 9 || exit 0
        # Remove existing block for this name
        sed -i "/^=== $name ===$/,/^=== END $name ===$/d" "$INFO_FILE" 2>/dev/null || true
        {
            echo "=== $name ==="
            echo "Folder: $dir"
            echo "Egress: $cc"
            echo "HTTP: $http"
            echo "SOCKS: $socks"
            echo "Binary: $bin"
            echo "StartScript: $start"
            echo "StartAllScript: $start_all"
            echo "Firejail: yes"
            echo "Files:"
            echo "$files"
            echo "Date: $(date -Is)"
            echo "=== END $name ==="
            echo
        } >> "$INFO_FILE"
    ) 9>>"$INFO_FILE"
}

# System INFO overview writer
info_write_system() {
    mkdir -p "$PSIPHON_BASE_DIR/psiphon"; [ -f "$INFO_FILE" ] || : > "$INFO_FILE"
    local psi="no" psi_path=""
    if [[ -x "/usr/bin/psiphon" ]]; then psi="yes"; psi_path="/usr/bin/psiphon";
    elif [[ -x "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then psi="yes"; psi_path="/usr/bin/psiphon-tunnel-core-x86_64"; fi
    local fj="no"; command -v firejail >/dev/null 2>&1 && fj="yes"
    local loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )
    local start_all="$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
    local autostart="unknown"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-enabled multifon-psiphon.service >/dev/null 2>&1; then autostart="enabled";
        elif systemctl is-active multifon-psiphon.service >/dev/null 2>&1; then autostart="active"; else autostart="disabled"; fi
    fi
    (
        flock -w 3 9 || exit 0
        sed -i "/^=== SYSTEM ===$/,/^=== END SYSTEM ===$/d" "$INFO_FILE" 2>/dev/null || true
        {
            echo "=== SYSTEM ==="
            echo "PsiphonInstalled: $psi"
            echo "PsiphonBinary: $psi_path"
            echo "FirejailInstalled: $fj"
            echo "LocationsCount: $loc_count"
            echo "StartAllScript: $start_all"
            echo "AutostartService: multifon-psiphon.service ($autostart)"
            echo "Date: $(date -Is)"
            echo "=== END SYSTEM ==="
            echo
        } >> "$INFO_FILE"
    ) 9>>"$INFO_FILE"
}

# Creating Psiphon folders
Creating_Psiphon_folders() {
   echo -e "${CYAN}🔧 Creating Psiphon folders...${RESET}"

   echo -e "📍 Available Psiphon location codes (use UPPERCASE two-letter codes):"
echo -e "   US, CA, GB, DE, NL, FR, IT, ES, SE, NO, DK, FI, PL, CZ, AT, IE, CH, BE, PT, GR, RO, HU, BG, HR, SI, SK, LT, LV, EE, TR, AE, SA, IN, SG, JP, KR, HK, TW, AU, NZ, BR, AR, CL, MX, ZA"
echo -e "   Example: AT,IE,GB"
echo -e "📍 Enter comma-separated country codes (UPPERCASE):"
   read -rp "➤ Country codes (UPPERCASE, comma-separated): " raw_countries
raw_countries=$(echo "$raw_countries" | tr '[:lower:]' '[:upper:]')
IFS=',' read -ra countries <<< "$raw_countries"

   echo -e "📁 Optionally enter folder names for each country (comma-separated, e.g., myat,myie,mygb). The prefix 'psiphon-' will be enforced automatically."
   echo -e "ℹ️  If left blank or mismatched count, default names will be used (psiphon-<cc>)"
   read -rp "➤ Folder names: " raw_names
   IFS=',' read -ra names <<< "$raw_names"

   used_ports=()
   http_port=8081
   socks_port=1081

   # Initialize and import persistent port registry
   port_registry_init
   mapfile -t _reserved_ports < <(port_registry_used_ports)
   if [[ ${#_reserved_ports[@]} -gt 0 ]]; then used_ports+=("${_reserved_ports[@]}"); fi

   # Also collect ports already present in existing config.json files
   collect_existing_ports

   # Ensure start script exists (skeleton) before adding locations
   generate_start_psiphon_script

   for i in "${!countries[@]}"; do
       cc="${countries[i]}"
       cc_trimmed=$(echo "$cc" | xargs | tr '[:lower:]' '[:upper:]')
       cc_lower=$(echo "$cc_trimmed" | tr '[:upper:]' '[:lower:]')
       name="${names[i]}"
       name=$(echo "$name" | xargs | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
       [[ -z "$name" ]] && name="psiphon-${cc_lower}"
       [[ "$name" != psiphon-* ]] && name="psiphon-$name"

       dir_path="$PSIPHON_BASE_DIR/psiphon/$name"
       mkdir -p "$dir_path"
       # Locate psiphon core binary from common paths
core_src=""
for p in "$PSIPHON_BASE_DIR/psiphon-tunnel-core" \
         "/usr/bin/psiphon-tunnel-core-x86_64" \
         "/etc/psiphon/psiphon-tunnel-core-x86_64" \
         "/etc/psiphon/psiphon-tunnel-core" \
         "/usr/bin/psiphon"; do
    [[ -x "$p" ]] && core_src="$p" && break
done
if [[ -z "$core_src" ]]; then
    echo -e "${RED}✗ Psiphon core not found (looked in: $PSIPHON_BASE_DIR, /usr/bin, /etc/psiphon). Skipping $name.${RESET}"
    continue
fi
cp "$core_src" "$dir_path/psiphon-tunnel-core-x86_64"
chmod +x "$dir_path/psiphon-tunnel-core-x86_64"

# Pick unique, available ports (prefer 8081–8091 and 1081–1091)
http_port_sel=$(next_free_port_in_range 8081 8091 || true)
[[ -z "$http_port_sel" ]] && http_port_sel=$(next_free_port_any 8081)
http_port="$http_port_sel"

socks_port_sel=$(next_free_port_in_range 1081 1091 || true)
[[ -z "$socks_port_sel" ]] && socks_port_sel=$(next_free_port_any 1081)
socks_port="$socks_port_sel"

       # Validate selected ports (fail-fast if empty)
       if ! [[ "$http_port" =~ ^[0-9]+$ ]] || ! [[ "$socks_port" =~ ^[0-9]+$ ]]; then
           echo -e "${RED}✗ Failed to allocate ports for $name. Skipping.${RESET}"
           continue
       fi

       # Create config using printf instead of heredoc to avoid EOF issues
       printf '{
"LocalHttpProxyPort":%s,
"LocalSocksProxyPort":%s,
"EgressRegion":"%s",
"PropagationChannelId":"FFFFFFFFFFFFFFFF",
"RemoteServerListDownloadFilename":"remote_server_list",
"RemoteServerListSignaturePublicKey":"MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=",
"RemoteServerListUrl":"https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed",
"SponsorId":"FFFFFFFFFFFFFFFF",
"UseIndistinguishableTLS":true
}
' "$http_port" "$socks_port" "$cc_trimmed" > "$dir_path/config.json"

       # Create per-instance start script (Firejail isolation)
       printf '#!/bin/bash
cd %q || exit 1
exec firejail --quiet --noprofile --private=. --whitelist=. --env=HOME=. --dns=1.1.1.1 --dns=8.8.8.8 ./psiphon-tunnel-core-x86_64 -config ./config.json
' "$dir_path" > "$dir_path/start.sh"
       chmod +x "$dir_path/start.sh"

       # Save allocation into registry (idempotent per name)
       port_registry_set_entry "$name" "$http_port" "$socks_port"

       # Write/update info registry
       info_write "$name" "$cc_trimmed" "$dir_path" "$http_port" "$socks_port"

       echo -e "${GREEN}✔ Created $name [Country: $cc_trimmed | HTTP: $http_port | SOCKS: $socks_port]${RESET}"

       used_ports+=("$http_port" "$socks_port")
       ((http_port++))
       ((socks_port++))

   # Append this location code to the start-psiphons.sh array (idempotent)
   :
   done

   # After creating folders, generate runner and enable autostart
   generate_start_psiphon_script
   setup_autostart_service
}

# Generate unified start script based on existing locations and enable autostart
generate_start_psiphon_script() {
    local root="$PSIPHON_BASE_DIR/psiphon"
    mkdir -p "$root"
    local script="$root/start-psiphons.sh"

    printf '%s
' \
'#!/bin/bash' \
'set -e' \
'' \
'dirs=()' \
'while IFS= read -r d; do dirs+=("$d"); done < <( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | sort -u )' \
'' \
'for d in "${dirs[@]}"; do' \
'  [ -d "$d" ] || continue' \
'  echo "Starting Psiphon: $(basename "$d")"' \
'  cd "$d" || { echo "ERROR: cannot cd into $d"; continue; }' \
'  # ensure binary name & executable' \
'  if [ ! -f psiphon-tunnel-core-x86_64 ] && [ -f psiphon-tunnel-core ]; then' \
'    mv psiphon-tunnel-core psiphon-tunnel-core-x86_64' \
'  fi' \
'  [ -f psiphon-tunnel-core-x86_64 ] && chmod +x psiphon-tunnel-core-x86_64 || {' \
'    echo "ERROR: missing binary in $d"; ls -l; cd - >/dev/null 2>&1 || true; continue; }' \
'  # config check' \
'  if [ ! -f config.json ]; then' \
'    echo "ERROR: missing config.json in $d"' \
'    cd - >/dev/null 2>&1 || true; continue' \
'  fi' \
'  # choose command (allow NO_FIREJAIL=1 to bypass sandbox for debugging)' \
'  CMD="firejail --quiet --noprofile --private=. --whitelist=. --env=HOME=. --dns=1.1.1.1 --dns=8.8.8.8 ./psiphon-tunnel-core-x86_64 -config config.json"' \
'  if [ -n "$NO_FIREJAIL" ]; then CMD="./psiphon-tunnel-core-x86_64 -config config.json"; fi' \
'  # if already have a pid but process dead, clear it' \
'  if [ -f psiphon.firejail.pid ]; then' \
'    pid=$(cat psiphon.firejail.pid)' \
'    if ! kill -0 "$pid" 2>/dev/null; then rm -f psiphon.firejail.pid; fi' \
'  fi' \
'  if [ ! -f psiphon.firejail.pid ]; then' \
'    nohup bash -c "$CMD" > log.txt 2>&1 &' \
'    echo $! > psiphon.firejail.pid' \
'    sleep 2' \
'    # quick health check' \
'    if ! kill -0 $(cat psiphon.firejail.pid 2>/dev/null) 2>/dev/null; then' \
'      echo "ERROR: process exited early in $(basename "$d")"' \
'      tail -n 40 log.txt 2>/dev/null || true' \
'    fi' \
'  else' \
'    echo "Already running (pid $(cat psiphon.firejail.pid))"' \
'  fi' \
'  cd - >/dev/null 2>&1 || true' \
'done' \
    > "$script"

    chmod +x "$script"
    echo -e "${GREEN}Generated:${RESET} $script"
}

add_location_to_start_script() {
    local code="$1"
    local script="$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
    [ -f "$script" ] || return
    # Normalize to UPPERCASE
    code=$(echo "$code" | tr '[:lower:]' '[:upper:]')
    # Skip if already present
    if grep -qE "^codes\+\=\($code\)$" "$script"; then
        return
    fi
    # Append as an array add to preserve structure
    printf 'codes+=(%s)
' "$code" >> "$script"
}

setup_autostart_service() {
    local root="$PSIPHON_BASE_DIR/psiphon"
    local script="$root/start-psiphons.sh"
    local service="/etc/systemd/system/multifon-psiphon.service"
    local homedir="$HOME"

    if [ ! -f "$script" ]; then
        echo -e "${RED}Start script not found, skipping autostart setup.${RESET}"
        return
    fi

    # Write systemd service using printf (no heredoc)
    sudo bash -c "printf '%s
' \
'[Unit]' \
'Description=Start multiple Psiphon instances with Firejail' \
'After=network-online.target' \
'Wants=network-online.target' \
'' \
'[Service]' \
'Type=oneshot' \
'User=${USER}' \
'WorkingDirectory=${homedir}' \
'ExecStart=/bin/bash ${script}' \
'RemainAfterExit=yes' \
'' \
'[Install]' \
'WantedBy=multi-user.target' > '${service}'"

    sudo systemctl daemon-reload
    sudo systemctl enable multifon-psiphon.service
    sudo systemctl restart multifon-psiphon.service
    echo -e "${GREEN}Autostart enabled via systemd:${RESET} multifon-psiphon.service"
}

# Psiphon bulk helpers (status/start/stop)
psiphon_dirs() {
    find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | sort -u
}

check_all_psiphon() {
    echo -e "${YELLOW}Psiphon status (by location):${RESET}"
    local any=0
    while IFS= read -r d; do
        any=1
        bn=$(basename "$d")
        cfg="$d/config.json"
        # read ports from config
        hp="-"; sp="-"
        if [ -f "$cfg" ]; then
            if command -v jq >/dev/null 2>&1; then
                hp=$(jq -r '.LocalHttpProxyPort // "-"' "$cfg")
                sp=$(jq -r '.LocalSocksProxyPort // "-"' "$cfg")
            else
                hp=$(grep -oE '"LocalHttpProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
                sp=$(grep -oE '"LocalSocksProxyPort"[[:space:]]*:[[:space:]]*[0-9]+' "$cfg" | grep -oE '[0-9]+' | head -n1)
                hp="${hp:--}"; sp="${sp:--}"
            fi
        fi
        # verify pid + process args
        running=0
        if [ -f "$d/psiphon.firejail.pid" ]; then
            pid=$(cat "$d/psiphon.firejail.pid")
            if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o args= | grep -q "psiphon-tunnel-core"; then
                running=1
            fi
        fi
        # fallback: check listening ports
        if [ "$running" -ne 1 ]; then
            detect=0
            if [[ "$hp" =~ ^[0-9]+$ ]]; then
                if command -v ss >/dev/null 2>&1; then ss -tuln 2>/dev/null | grep -q ":$hp\>" && detect=1; else netstat -tuln 2>/dev/null | grep -q ":$hp\>" && detect=1; fi
            fi
            if [[ "$sp" =~ ^[0-9]+$ ]] && [ "$detect" -ne 1 ]; then
                if command -v ss >/dev/null 2>&1; then ss -tuln 2>/dev/null | grep -q ":$sp\>" && detect=1; else netstat -tuln 2>/dev/null | grep -q ":$sp\>" && detect=1; fi
            fi
            [ "$detect" -eq 1 ] && running=1
        fi
        if [ "$running" -eq 1 ]; then
            echo -e " ${GREEN}RUNNING${RESET}  $bn  ${WHITE}(HTTP:$hp SOCKS:$sp)${RESET}"
        else
            echo -e " ${RED}STOPPED${RESET}  $bn  ${WHITE}(HTTP:$hp SOCKS:$sp)${RESET}"
        fi
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
    pause
}

start_all_psiphon() {
    generate_start_psiphon_script
    bash "$HOME/psiphon/start-psiphons.sh"
    sleep 1
    check_all_psiphon
}

start_all_psiphon_quiet() {
    generate_start_psiphon_script
    bash "$HOME/psiphon/start-psiphons.sh" >/dev/null 2>&1 || true
}

stop_all_psiphon_quiet() {
    while IFS= read -r d; do
        if [ -f "$d/psiphon.firejail.pid" ]; then
            pid=$(cat "$d/psiphon.firejail.pid")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
            fi
            rm -f "$d/psiphon.firejail.pid"
        fi
    done < <(psiphon_dirs)
}

restart_all_psiphon() {
    echo -e "${YELLOW}Restarting all Psiphon locations...${RESET}"
    stop_all_psiphon_quiet
    start_all_psiphon_quiet
    echo -e "${GREEN}Restart complete.${RESET}"
    pause
}

stop_all_psiphon() {
    echo -e "${YELLOW}Stopping all Psiphon locations...${RESET}"
    local any=0
    while IFS= read -r d; do
        any=1
        if [ -f "$d/psiphon.firejail.pid" ]; then
            pid=$(cat "$d/psiphon.firejail.pid")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
                echo -e "${GREEN}Stopped${RESET} $(basename "$d") (pid $pid)"
            fi
            rm -f "$d/psiphon.firejail.pid"
        fi
    done < <(psiphon_dirs)
    [ "$any" -eq 0 ] && echo -e "${RED}No psiphon-* locations found.${RESET}"
    pause
}

# Creating Psiphon folders (no Firejail) - under repair
Creating_Psiphon_folders_no_firejail() {
    echo -e "${YELLOW}This option is under repair. Please use option 1 (with Firejail) for now.${RESET}"
    pause
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
    while true; do
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
            1) rm -rf $HOME/psiphon-* && echo -e "${GREEN}All Psiphon folders removed.${RESET}"; info_write_system; pause ;;
            2) sudo apt purge firejail -y && echo -e "${GREEN}Firejail removed.${RESET}"; info_write_system; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}


# Main loop
while true; do
    clear
    logo
    check_status
    main_menu
    echo ""
    read -rp "Select an option [0-4]: " Main
    case $Main in
        1) install_psiphon_menu ;;
        2) install_firejail ;;
        3) psiphon_folder_menu ;;
        4) cleanup_menu ;;
        # 5) cleanup_menu ;;  # removed; cleanup now at 4
        0) echo -e "${CYAN}Exiting...${RESET}"; exit ;;
        *) echo -e "${RED}Invalid option. Please try again.${RESET}" ;;
    esac
done
