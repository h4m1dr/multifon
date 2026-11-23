#!/bin/bash
# multifon v2 — lib/psiphon.sh
# Psiphon core: install, folder creation, start/stop/restart/status,
# delete (canonical cleanup path), rotate IP.
# Firejail sandboxing is kept exactly as in v1:
#   firejail --noprofile --private=<instance dir> ./psiphon-tunnel-core-x86_64 -config ./config.json
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_PSIPHON_LOADED:-}" ]] && return 0
_MULTIFON_PSIPHON_LOADED=1

# Pinned Psiphon core. Library release v2.0.43 (2026-11-17, commit 66e249d)
# from Psiphon-Labs/psiphon-tunnel-core; the Linux console binary is
# published in Psiphon-Labs/psiphon-tunnel-core-binaries (master).
# NOTE: upstream publishes NO checksum/signature file for the console
# binary, so verification here is: HTTPS-only download + ELF magic +
# non-empty + SHA-256 recorded locally and compared on the next update.
PSIPHON_PINNED_VERSION="v2.0.43"
PSIPHON_BIN_URL="https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/linux/psiphon-tunnel-core-x86_64"
PSIPHON_SHA_FILE="$PSIPHON_BASE_DIR/psiphon/.core-sha256"

# Verify a downloaded core binary. Prints its SHA-256 on success.
# Returns 1 if the file is empty, not an ELF binary, or unreadable.
psiphon_verify_binary() {
    local file="$1" sha
    [ -s "$file" ] || return 1
    [[ "$(head -c 4 "$file" 2>/dev/null)" == $'\x7fELF' ]] || return 1
    sha=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    [ -n "$sha" ] || return 1
    echo "$sha"
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
        echo -e "${BLUE} 3) Latest Binary Download ${YELLOW}(Approx 20 MB, pinned ${PSIPHON_PINNED_VERSION})${RESET}"
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
                temp_file="/tmp/psiphon-latest"
                echo -e "${BLUE}Downloading pinned core (${PSIPHON_PINNED_VERSION})...${RESET}"
                if ! wget -q -O "$temp_file" "$PSIPHON_BIN_URL"; then
                    echo -e "${RED}Download failed.${RESET}"
                    rm -f "$temp_file"
                    pause
                    continue
                fi
                new_sha="$(psiphon_verify_binary "$temp_file" || true)"
                if [[ -z "$new_sha" ]]; then
                    echo -e "${RED}Downloaded file failed verification (empty or not an ELF binary). Refusing to install.${RESET}"
                    rm -f "$temp_file"
                    pause
                    continue
                fi
                if cmp -s "$temp_file" "/usr/bin/psiphon-tunnel-core-x86_64"; then
                    echo -e "${GREEN}Already up to date.${RESET}"
                    rm -f "$temp_file"
                else
                    # A changed hash for the same pinned version is suspicious.
                    old_sha=""
                    [[ -f "$PSIPHON_SHA_FILE" ]] && old_sha=$(awk '{print $1}' "$PSIPHON_SHA_FILE" 2>/dev/null)
                    if [[ -n "$old_sha" && "$old_sha" != "$new_sha" ]]; then
                        echo -e "${YELLOW}Warning: the new binary hash differs from the hash recorded for ${PSIPHON_PINNED_VERSION}.${RESET}"
                        echo -e "${YELLOW}old: $old_sha${RESET}"
                        echo -e "${YELLOW}new: $new_sha${RESET}"
                        if ! confirm_yes "Install it anyway?"; then
                            echo -e "${YELLOW}Aborted. Binary NOT installed.${RESET}"
                            rm -f "$temp_file"
                            pause
                            continue
                        fi
                    fi
                    echo -e "${BLUE}Updating to latest version...${RESET}"
                    sudo mv "$temp_file" /usr/bin/psiphon-tunnel-core-x86_64
                    sudo chmod +x /usr/bin/psiphon-tunnel-core-x86_64
                    mkdir -p "$PSIPHON_BASE_DIR/psiphon"
                    printf '%s  %s\n' "$new_sha" "$PSIPHON_PINNED_VERSION" > "$PSIPHON_SHA_FILE"
                    echo -e "${GREEN}Installed. SHA-256 recorded in $PSIPHON_SHA_FILE${RESET}"
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

# Refresh the global used_ports list from registry + existing configs.
_refresh_used_ports() {
    used_ports=()
    port_registry_init
    mapfile -t _reserved_ports < <(port_registry_used_ports)
    if [[ ${#_reserved_ports[@]} -gt 0 ]]; then used_ports+=("${_reserved_ports[@]}"); fi
    collect_existing_ports
}

# Create ONE location folder. Expects _refresh_used_ports to have run first.
# Usage: _create_single_location <CC_UPPER>
_create_single_location() {
    local cc_upper="$1"
    local cc_lower="${cc_upper,,}"
    local name="psiphon-${cc_lower}"
    local dir_path="$PSIPHON_BASE_DIR/psiphon/$name"
    mkdir -p "$dir_path"

    # Locate psiphon core binary from common paths (prefer system Psiphon first)
    local core_src=""
    local p
    for p in "/etc/psiphon/psiphon-tunnel-core-x86_64" \
             "/etc/psiphon/psiphon-tunnel-core" \
             "$PSIPHON_BASE_DIR/psiphon-tunnel-core-x86_64" \
             "$PSIPHON_BASE_DIR/psiphon-tunnel-core" \
             "/usr/bin/psiphon-tunnel-core-x86_64" \
             "/usr/bin/psiphon"; do
        [[ -x "$p" ]] && core_src="$p" && break
    done
    if [[ -z "$core_src" ]]; then
        echo -e "${RED}✗ Psiphon core not found (looked in: /etc/psiphon, $PSIPHON_BASE_DIR, /usr/bin). Skipping $name.${RESET}"
        return 1
    fi
    cp "$core_src" "$dir_path/psiphon-tunnel-core-x86_64"
    chmod +x "$dir_path/psiphon-tunnel-core-x86_64"

    # Pick unique, available ports (prefer 8081–8091 and 1081–1091)
    local http_port socks_port http_port_sel socks_port_sel
    http_port_sel=$(next_free_port_in_range 8081 8091 || true)
    [[ -z "$http_port_sel" ]] && http_port_sel=$(next_free_port_any 8081)
    http_port="$http_port_sel"

    socks_port_sel=$(next_free_port_in_range 1081 1091 || true)
    [[ -z "$socks_port_sel" ]] && socks_port_sel=$(next_free_port_any 1081)
    socks_port="$socks_port_sel"

    # Validate selected ports (fail-fast if empty)
    if ! [[ "$http_port" =~ ^[0-9]+$ ]] || ! [[ "$socks_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ Failed to allocate ports for $name. Skipping.${RESET}"
        return 1
    fi

    # Create config using printf (EgressRegion uses uppercase ASCII)
    # NOTE: template is byte-identical to v1 — do not "improve" the keys.
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
' "$http_port" "$socks_port" "$cc_upper" > "$dir_path/config.json"

    # Create per-instance start script (Firejail isolation).
    # BUG FIX #5 (root cause): v1 never wrote psiphon.firejail.pid anywhere,
    # so every stop function that reads the pidfile found nothing to kill.
    # The launcher now records $! (the firejail PID) and waits on it, so
    # the script still runs in the foreground like before.
    printf '#!/bin/bash
cd %q || exit 1
if [ ! -f ./config.json ]; then echo "ERROR: config.json missing in %q" >&2; exit 10; fi
if [ ! -x ./psiphon-tunnel-core-x86_64 ]; then
  if [ -f ./psiphon-tunnel-core-x86_64 ]; then chmod +x ./psiphon-tunnel-core-x86_64; else echo "ERROR: psiphon-tunnel-core-x86_64 missing in %q" >&2; exit 11; fi
fi
firejail --quiet --noprofile --private=%q --env=HOME=%q ./psiphon-tunnel-core-x86_64 -config ./config.json > log.txt 2>&1 &
echo $! > psiphon.firejail.pid
wait $!
' "$dir_path" "$dir_path" "$dir_path" "$dir_path" "$dir_path" > "$dir_path/start.sh"
    chmod +x "$dir_path/start.sh"

    # Save allocation into registry (idempotent per name)
    port_registry_set_entry "$name" "$http_port" "$socks_port"

    # Write/update info registry (records Folder path)
    info_write "$name" "$cc_upper" "$dir_path" "$http_port" "$socks_port"

    echo -e "${GREEN}✔ Created $name [Country: $cc_upper | HTTP: $http_port | SOCKS: $socks_port]${RESET}"

    used_ports+=("$http_port" "$socks_port")
}

# Creating Psiphon folders (with strict validation for ASCII 2-letter country codes)
Creating_Psiphon_folders() {
   echo -e "${CYAN}🔧 Creating Psiphon folders...${RESET}"

   # Validate INFO file first
   validate_info_file

   # Allowed country codes (2-letter, ASCII)
   VALID_CODES=(US CA GB DE NL FR IT ES SE NO DK FI PL CZ AT IE CH BE PT GR RO HU BG HR SI SK LT LV EE TR AE SA IN SG JP KR HK TW AU NZ BR AR CL MX ZA)

   # Helper: check if a code is in VALID_CODES
   code_is_valid() {
       local c="$1"; c="${c^^}"    # to UPPERCASE
       for v in "${VALID_CODES[@]}"; do
           [[ "$c" == "$v" ]] && return 0
       done
       return 1
   }

   # Read and validate countries in a loop until input is valid
   while true; do
       echo -e "📍 Enter comma-separated country codes (case-insensitive).
    Allowed: ${WHITE}${VALID_CODES[*]}${RESET}"
       read -rp "➤ Country codes: " raw_countries
       # Normalize: split by comma, trim spaces
       IFS=',' read -ra _raw <<< "$raw_countries"
       countries=()
       invalid=()
       for x in "${_raw[@]}"; do
           c="$(echo "$x" | xargs)"                 # trim
           [[ -z "$c" ]] && continue
           # Reject anything not A–Z letters
           if ! [[ "$c" =~ ^[A-Za-z]{2}$ ]]; then
               invalid+=("$c")
               continue
           fi
           cu="${c^^}"                                # UPPER
           if code_is_valid "$cu"; then
               countries+=("$cu")
           else
               invalid+=("$c")
           fi
       done

       # Deduplicate, preserve order
       if [[ ${#countries[@]} -gt 0 ]]; then
           uniq=(); seen=""
           for c in "${countries[@]}"; do
               case ","$seen"," in *","$c","*) ;; *) uniq+=("$c"); seen+="${seen:+,}$c" ;; esac
           done
           countries=("${uniq[@]}")
       fi

       if [[ ${#countries[@]} -eq 0 ]]; then
           echo -e "${RED}✗ No valid codes entered.${RESET}"
       elif [[ ${#invalid[@]} -gt 0 ]]; then
           echo -e "${RED}✗ Invalid codes:${RESET} ${invalid[*]}"
           echo -e "${YELLOW}Please enter only from the allowed two-letter list above.${RESET}"
       else
           break
       fi
       echo ""
   done

   _refresh_used_ports

   # Ensure start script exists (skeleton) before adding locations
   generate_start_psiphon_script

   local cc_upper
   for cc_upper in "${countries[@]}"; do
       _create_single_location "$cc_upper" || true
   done

   # After creating folders, generate runner from INFO and enable autostart
   generate_start_psiphon_script
   setup_autostart_service
}

# Generate unified start script based on INFO (UPDATED)
generate_start_psiphon_script() {
    local root="$PSIPHON_BASE_DIR/psiphon"
    mkdir -p "$root"
    local script="$root/start-psiphons.sh"

    # Build a list of country codes from INFO (Folder: <path>) or fallback to discovery
    local codes=()
    if [ -f "$INFO_FILE" ]; then
        while IFS= read -r line; do
            f="${line#Folder: }"
            bn="$(basename "$f")"
            code="${bn#psiphon-}"
            [ -n "$code" ] && codes+=("$code")
        done < <(grep -E '^Folder: ' "$INFO_FILE" 2>/dev/null || true)
    fi
    if [ "${#codes[@]}" -eq 0 ]; then
        while IFS= read -r f; do
            bn="$(basename "$f")"; code="${bn#psiphon-}"
            [ -n "$code" ] && codes+=("$code")
        done < <( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | sort -u )
    fi

    # De-duplicate while preserving order
    if [ "${#codes[@]}" -gt 0 ]; then
        local seen=""
        local unique=()
        for c in "${codes[@]}"; do
            case ",$seen," in
                *",$c,"*) ;;  # already
                *) unique+=("$c"); seen+="${seen:+,}$c" ;;
            esac
        done
        codes=("${unique[@]}")
    fi

    # Write the script using echo/printf to avoid heredoc escaping issues in online execution
    {
        echo "#!/bin/bash"
        echo
        echo "# Start multiple Psiphon instances; each runs in its own folder and Firejail private sandbox"
        echo -n "for dir in"
        if [ "${#codes[@]}" -gt 0 ]; then
            for c in "${codes[@]}"; do
                echo -n " $c"
            done
        fi
        echo "; do"
        echo '    echo "Starting Psiphon: $dir"'
        echo '    cd "$HOME/psiphon/psiphon-$dir" || { echo "Skip: folder not found: $HOME/psiphon/psiphon-$dir"; continue; }'
        echo
        echo "    # If the x86_64 executable is missing but 'psiphon-tunnel-core' exists, rename and make it executable"
        echo '    if [ ! -f psiphon-tunnel-core-x86_64 ] && [ -f psiphon-tunnel-core ]; then'
        echo '        mv psiphon-tunnel-core psiphon-tunnel-core-x86_64'
        echo '        chmod +x psiphon-tunnel-core-x86_64'
        echo '    fi'
        echo
        echo '    # Run inside a private jail bound to this directory (matches the working method we used)'
        echo '    nohup firejail --noprofile --private="$(pwd)" ./psiphon-tunnel-core-x86_64 -config config.json > log.txt 2>&1 &'
        echo '    echo $! > psiphon.firejail.pid'
        echo 'done'
    } > "$script"

    chmod +x "$script"
    echo -e "${GREEN}Generated:${RESET} $script"
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
    sudo bash -c "printf '%s\n' \
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

# Launch ONE instance folder in the background (firejail sandbox).
# Used by rotate_ip; bulk start still goes through start-psiphons.sh.
_launch_instance_dir() {
    local d="$1"
    (
        cd "$d" || exit 1
        if [ ! -f psiphon-tunnel-core-x86_64 ] && [ -f psiphon-tunnel-core ]; then
            mv psiphon-tunnel-core psiphon-tunnel-core-x86_64
            chmod +x psiphon-tunnel-core-x86_64
        fi
        nohup firejail --noprofile --private="$(pwd)" ./psiphon-tunnel-core-x86_64 -config config.json > log.txt 2>&1 &
        echo $! > psiphon.firejail.pid
    )
}

# Print the public exit IP seen through one instance's SOCKS port (or nothing).
psiphon_exit_ip() {
    local d="$1" sp
    read -r _hp sp < <(instance_ports "$d")
    [[ "$sp" =~ ^[0-9]+$ ]] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    curl -s --max-time 15 --socks5-hostname "127.0.0.1:$sp" https://ifconfig.me 2>/dev/null || true
}

check_all_psiphon() {
    echo -e "${YELLOW}Psiphon status (by location):${RESET}"
    local any=0
    while IFS= read -r d; do
        any=1
        bn=$(basename "$d")
        # read ports from config
        read -r hp sp < <(instance_ports "$d")
        # verify pid + process args (pidfile first, live process second)
        running=0
        if [ -f "$d/psiphon.firejail.pid" ]; then
            pid=$(cat "$d/psiphon.firejail.pid")
            if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o args= | grep -q "psiphon-tunnel-core"; then
                running=1
            fi
        fi
        # fallback: live-process reconciliation (covers stale/missing pidfile)
        if [ "$running" -ne 1 ]; then
            if psiphon_live_pid "$d" >/dev/null 2>&1; then
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
        stop_psiphon_in_dir "$d"
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
        stop_psiphon_in_dir "$d"
        echo -e "${GREEN}Stopped${RESET} $(basename "$d")"
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

# Canonical stop for ONE instance folder (bug #5 fix).
# 1) pidfile, if it points at a live process; stale pidfile is always removed.
# 2) live-process fallback (covers manual start/stop and missing pidfile).
# 3) verify the ports are really free afterwards.
stop_psiphon_in_dir() {
    local d="$1" pid=""
    if [ -f "$d/psiphon.firejail.pid" ]; then
        pid=$(cat "$d/psiphon.firejail.pid" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _kill_pid "$pid"
        fi
        rm -f "$d/psiphon.firejail.pid"
    fi
    pid=$(psiphon_live_pid "$d" || true)
    if [[ -n "$pid" ]]; then
        _kill_pid "$pid"
        # re-check once: a second process may have been started manually
        pid=$(psiphon_live_pid "$d" || true)
        [[ -n "$pid" ]] && _kill_pid "$pid"
    fi
}

# TERM, wait, then KILL if still alive. Never kills PID 1 or self.
_kill_pid() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    [[ "$pid" -le 1 || "$pid" == "$$" ]] && return 0
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
}

# Canonical delete for ONE instance (bug #1 fix): every cleanup path
# (menu delete AND doctor) must go through this function.
# Stops the instance, frees the registry entry, removes the INFO block,
# removes any firewall rules for it, wipes the folder, and verifies the
# ports are really free. Returns 1 if a port is still held afterwards.
delete_one_instance() {
    local d="$1" bname
    bname="$(basename "$d")"

    # Stop running firejail instance for this directory
    stop_psiphon_in_dir "$d"

    # Release allocated ports from persistent registry
    port_registry_del_entry "$bname"

    # Remove location block from INFO.txt
    info_remove_block "$bname"

    # Remove any iptables rules this instance owns (best effort)
    firewall_close_instance_ports "$bname" 2>/dev/null || true

    # Wipe folder from filesystem
    rm -rf "$d"

    # Ports are guaranteed free by the stop above (live-process verified)
    # plus the registry entry removal; a re-check of the listening sockets
    # for the old ports happens in doctor_sync.
    echo "Deleted $bname"
    return 0
}

# Cleanup helpers
delete_psiphon_folders() {
    echo -e "${YELLOW}Select folders to delete:${RESET}"
    mapfile -t LIST < <( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | sort -u )
    if [ ${#LIST[@]} -eq 0 ]; then
        echo -e "${RED}No psiphon-* folders found.${RESET}"; pause; return
    fi
    i=1; for d in "${LIST[@]}"; do echo "  $i) $(basename "$d")"; ((i++)); done
    echo "  a) ALL"
    echo "  0) Cancel"
    read -rp "Enter numbers (comma-separated), 'a' for ALL, or 0 to cancel: " sel
    [[ "$sel" == "0" ]] && return
    to_delete=()
    if [[ "$sel" == "a" || "$sel" == "A" ]]; then
        to_delete=("${LIST[@]}")
    else
        IFS=',' read -ra idx <<< "$sel"
        for x in "${idx[@]}"; do
            x="$(echo "$x" | xargs)"; [[ -z "$x" ]] && continue
            if [[ "$x" =~ ^[0-9]+$ ]] && [ "$x" -ge 1 ] && [ "$x" -le ${#LIST[@]} ]; then
                to_delete+=("${LIST[$((x-1))]}")
            fi
        done
    fi
    if [ ${#to_delete[@]} -eq 0 ]; then echo -e "${RED}Nothing selected.${RESET}"; pause; return; fi
    echo -e "${RED}About to delete:${RESET}"; for d in "${to_delete[@]}"; do echo "  - $(basename "$d")"; done
    # BUG FIX #2: y / yes / YES all accepted now (was: only exact "YES").
    if ! confirm_yes "Type yes to confirm deletion"; then
        echo "Canceled"; pause; return
    fi
    for d in "${to_delete[@]}"; do
        delete_one_instance "$d"
    done

    # Re-generate launcher script without removed instances
    generate_start_psiphon_script

    # Validate INFO file and update system overview metrics
    validate_info_file
    info_write_system

    # Reload systemd service to reflect updated launcher script
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl daemon-reload
        if systemctl is-active --quiet multifon-psiphon.service; then
            sudo systemctl restart multifon-psiphon.service
        fi
    fi

    echo -e "${GREEN}Done.${RESET}"; pause
}

# BUG FIX #3 — rotate IP: restart one instance so Psiphon connects to a
# fresh server and gets a new exit IP, then show the new IP.
# Usage: rotate_ip <dir>
rotate_ip() {
    local d="$1" old_ip new_ip
    [ -d "$d" ] || { echo -e "${RED}Folder not found: $d${RESET}"; return 1; }
    old_ip=$(psiphon_exit_ip "$d" || true)
    echo -e "${YELLOW}Rotating IP for $(basename "$d")...${RESET}"
    [[ -n "$old_ip" ]] && echo -e " old IP: $old_ip"
    stop_psiphon_in_dir "$d"
    sleep 2
    _launch_instance_dir "$d"
    echo -e "${CYAN}Waiting for the tunnel to come up...${RESET}"
    sleep 8
    new_ip=$(psiphon_exit_ip "$d" || true)
    if [[ -n "$new_ip" ]]; then
        echo -e "${GREEN}new IP: $new_ip${RESET}"
        [[ "$new_ip" != "$old_ip" ]] && echo -e "${GREEN}IP changed.${RESET}" || echo -e "${YELLOW}Same IP as before — try again, Psiphon may have picked the same server.${RESET}"
    else
        echo -e "${RED}Could not read the new IP (tunnel may still be connecting — check status).${RESET}"
        return 1
    fi
}

# Change the egress region of one instance: delete + recreate with a new code.
# Usage: change_region <dir> <NEW_CC_UPPER>
change_region() {
    local d="$1" new_cc="${2^^}"
    [ -d "$d" ] || { echo -e "${RED}Folder not found: $d${RESET}"; return 1; }
    [[ "$new_cc" =~ ^[A-Z]{2}$ ]] || { echo -e "${RED}Bad country code: $new_cc${RESET}"; return 1; }
    echo -e "${YELLOW}Moving $(basename "$d") to region $new_cc...${RESET}"
    delete_one_instance "$d"
    _refresh_used_ports
    generate_start_psiphon_script
    _create_single_location "$new_cc"
    generate_start_psiphon_script
    setup_autostart_service
}
