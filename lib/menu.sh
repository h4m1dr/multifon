#!/bin/bash
# multifon v2 — lib/menu.sh
# Menus + main loop + PATH install (bug #4).
# Menu numbers 1–4 are the same as v1; 5–9 are the new v2 sections.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_MENU_LOADED:-}" ]] && return 0
_MULTIFON_MENU_LOADED=1

# Main menu display
main_menu() {
    echo -e "${YELLOW}Main Menu:${RESET}"
    echo ""
    echo -e "${BLUE} 1) Psiphon Installation Menu ${YELLOW}#Source: SpherionOS${RESET}"
    echo -e "${BLUE} 2) Install Firejail ${YELLOW}(Approx 5.5 MB)${RESET}"
    echo ""
    echo -e "${BLUE} 3) Psiphon Folder Management${RESET}"
    echo -e "${BLUE} 4) Cleanup Options${RESET}"
    echo -e "${BLUE} 5) Doctor & Repair ${YELLOW}(sync registry, fix pidfiles)${RESET}"
    echo -e "${BLUE} 6) Firewall ${YELLOW}(iptables open/block ports)${RESET}"
    echo -e "${BLUE} 7) Cores ${YELLOW}(WARP / Tor / Geph / Arman — see cores.yaml)${RESET}"
    echo -e "${BLUE} 8) Force DNS ${YELLOW}(leak check, scoped port-53 + STUN block)${RESET}"
    echo -e "${BLUE} 9) Install 'multifon' command on PATH${RESET}"
    echo -e "${BLUE} 10) Updates ${YELLOW}(Psiphon core + Firejail)${RESET}"
    echo -e "${BLUE} 11) Fix ${YELLOW}(run the checklist: health, DNS, rotate dirty IPs)${RESET}"
    echo ""
    echo -e "${BLUE} 0) Exit${RESET}"
}

# 3) Psiphon Folder Management (v1 options 1–6 kept, 7–9 are new)
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
        echo -e "${BLUE} 7) Rotate IP (one location)${RESET}"
        echo -e "${BLUE} 8) Change region (one location)${RESET}"
        echo -e "${BLUE} 9) Health check (all locations)${RESET}"
        echo -e "${BLUE} 10) Create recommended country set ${WHITE}(DE / NL / SE / SG — Phase 5)${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-10]: " psiphon_folder
        case $psiphon_folder in
            1) Creating_Psiphon_folders ;;
            2) Creating_Psiphon_folders_no_firejail ;;
            3) check_all_psiphon ;;
            4) start_all_psiphon ;;
            5) stop_all_psiphon ;;
            6) restart_all_psiphon ;;
            7)
                d=$(select_psiphon_dir "Rotate IP for which location?" || true)
                [[ -n "$d" ]] && { rotate_ip "$d"; pause; }
                ;;
            8)
                d=$(select_psiphon_dir "Change region for which location?" || true)
                if [[ -n "$d" ]]; then
                    read -rp "New country code (2 letters, e.g. DE): " new_cc
                    change_region "$d" "$new_cc"
                    pause
                fi
                ;;
            9) health_check_all; pause ;;
            10) create_recommended_country_set; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# Pick one psiphon-* folder interactively. Prints the dir path, or nothing.
select_psiphon_dir() {
    local prompt="$1" i=1 d
    mapfile -t _dirs < <(psiphon_dirs)
    if [ ${#_dirs[@]} -eq 0 ]; then
        echo -e "${RED}No psiphon-* folders found.${RESET}" >&2
        return 1
    fi
    echo -e "${YELLOW}$prompt${RESET}" >&2
    for d in "${_dirs[@]}"; do echo "  $i) $(basename "$d")"; ((i++)); done >&2
    echo "  0) Cancel" >&2
    read -rp "Select [0-${#_dirs[@]}]: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#_dirs[@]} ] \
        && echo "${_dirs[$((sel-1))]}" && return 0
    return 1
}

# 4) Cleanup menu (v1 options kept)
cleanup_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Cleanup Options:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Delete Psiphon Folders (select or ALL)${RESET}"
        echo -e "${BLUE} 2) Remove Firejail${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-2]: " clean_option
        case $clean_option in
            1) delete_psiphon_folders ;;
            2) sudo apt purge -y firejail && echo -e "${GREEN}Firejail removed.${RESET}"; info_write_system; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# 5) Doctor & Repair menu
doctor_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Doctor & Repair:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Sync & repair now ${WHITE}(prune orphans, fix pidfiles, re-register folders)${RESET}"
        echo -e "${BLUE} 2) Health check (exit IP + latency + blacklist)${RESET}"
        echo -e "${BLUE} 3) Health check — all cores ${WHITE}(WARP / Tor / Arman)${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-3]: " doc_opt
        case $doc_opt in
            1) doctor_sync; pause ;;
            2) health_check_all; pause ;;
            3) health_check_cores_all; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# 6) Firewall menu (bug #7)
firewall_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Firewall (backend: $(firewall_backend || echo none)):${RESET}"
        echo ""
        echo -e "${BLUE} 1) Open a port (INPUT ACCEPT)${RESET}"
        echo -e "${BLUE} 2) Block a port (INPUT DROP)${RESET}"
        echo -e "${BLUE} 3) List multifon rules${RESET}"
        echo -e "${BLUE} 4) Remove one instance's rules${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-4]: " fw_opt
        case $fw_opt in
            1)
                read -rp "Port to open: " p
                read -rp "Name/tag for the rule (e.g. psiphon-cz): " n
                firewall_open_port "$p" "${n:-manual}"
                pause
                ;;
            2)
                read -rp "Port to block: " p
                read -rp "Name/tag for the rule (e.g. psiphon-cz): " n
                firewall_block_port "$p" "${n:-manual}"
                pause
                ;;
            3) firewall_list; pause ;;
            4)
                read -rp "Instance name whose rules to remove (e.g. psiphon-cz): " n
                firewall_close_instance_ports "$n"
                echo -e "${GREEN}Done.${RESET}"
                pause
                ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# 7) Cores menu (bug #8)
cores_menu() {
    while true; do
        clear
        logo
        check_status
        cores_show_all
        echo -e "${YELLOW}Cores:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Install WARP core (wireproxy, test-only — see docs/TEST-WARP-TOR.md)${RESET}"
        echo -e "${BLUE} 2) Install Tor core (test-only — see docs/TEST-WARP-TOR.md)${RESET}"
        echo -e "${BLUE} 3) Install Geph core (stub — not wired yet)${RESET}"
        echo -e "${BLUE} 4) Install Arman VPN core (stub — headless use verified, needs your sign-in)${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-4]: " core_opt
        case $core_opt in
            1) core_install_warp; pause ;;
            2) core_install_tor; pause ;;
            3) core_install_geph; pause ;;
            4) core_install_arman; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# 8) Force DNS menu
dns_menu() {
    while true; do
        clear
        logo
        check_status
        dns_force_status
        echo ""
        echo -e "${YELLOW}DoH forwarders (per-egress, dnscrypt-proxy):${RESET}"
        dns_forwarder_status
        echo ""
        echo -e "${YELLOW}Force DNS:${RESET}"
        echo ""
        echo -e "${BLUE} 1) DNS leak check (all locations)${RESET}"
        echo -e "${BLUE} 2) Enable scoped port-53 + STUN block ${YELLOW}(sandbox user only — Xray keeps working)${RESET}"
        echo -e "${BLUE} 3) Disable scoped port-53 + STUN block${RESET}"
        echo -e "${BLUE} 4) Start per-egress DoH forwarders ${WHITE}(all running egresses)${RESET}"
        echo -e "${BLUE} 5) Stop all DoH forwarders${RESET}"
        echo -e "${BLUE} 6) DoH forwarder status${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-6]: " dns_opt
        case $dns_opt in
            1) dns_leak_check_all; pause ;;
            2) dns_force_enable; pause ;;
            3) dns_force_disable; pause ;;
            4) dns_forwarder_start_all; pause ;;
            5) dns_forwarder_stop_all; pause ;;
            6) dns_forwarder_status; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# 9) Install 'multifon' on PATH (bug #4) — the menu opens from anywhere.
install_multifon_command() {
    local target="/usr/local/bin/multifon"
    echo -e "${CYAN}Installing 'multifon' command -> $target${RESET}"
    chmod +x "$MULTIFON_DIR/multifon.sh"
    if [[ -L "$target" || -f "$target" ]]; then
        echo -e "${YELLOW}Existing $target will be replaced.${RESET}"
    fi
    if sudo ln -sf "$MULTIFON_DIR/multifon.sh" "$target"; then
        echo -e "${GREEN}Installed.${RESET}"
    else
        echo -e "${RED}Failed to create the symlink (need sudo).${RESET}"
        pause
        return 1
    fi
    if command -v multifon >/dev/null 2>&1; then
        echo -e "${GREEN}Try it from anywhere: multifon${RESET}"
    else
        echo -e "${YELLOW}'multifon' is installed but /usr/local/bin is not in your PATH.${RESET}"
        echo -e "${YELLOW}Add this to ~/.bashrc: export PATH=\"\$PATH:/usr/local/bin\"${RESET}"
    fi
    pause
}

# 10) Updates menu (v2.1 — user-reported missing)
updates_menu() {
    while true; do
        clear
        logo
        check_status
        echo -e "${YELLOW}Updates:${RESET}"
        echo ""
        echo -e "${BLUE} 1) Update Psiphon core ${WHITE}(pinned ${PSIPHON_PINNED_VERSION}; refreshes every instance copy)${RESET}"
        echo -e "${BLUE} 2) Update Firejail ${WHITE}(apt upgrade)${RESET}"
        echo -e "${BLUE} 3) Check upstream versions ${WHITE}(pinned vs latest — read-only)${RESET}"
        echo ""
        echo -e "${BLUE} 0) Back to Main Menu${RESET}"
        echo ""
        read -rp "Select an option [0-3]: " upd_opt
        case $upd_opt in
            1) update_psiphon_core; pause ;;
            2) update_firejail; pause ;;
            3) check_upstream_versions; pause ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${RESET}"; pause ;;
        esac
    done
}

# Main loop
main_loop() {
    while true; do
        clear
        logo
        check_status
        main_menu
        echo ""
        read -rp "Select an option [0-11]: " Main
        case $Main in
            1) install_psiphon_menu ;;
            2) install_firejail ;;
            3) psiphon_folder_menu ;;
            4) cleanup_menu ;;
            5) doctor_menu ;;
            6) firewall_menu ;;
            7) cores_menu ;;
            8) dns_menu ;;
            9) install_multifon_command ;;
            10) updates_menu ;;
            11) multifon_fix; pause ;;
            0) echo -e "${CYAN}Exiting...${RESET}"; exit ;;
            *) echo -e "${RED}Invalid option. Please try again.${RESET}" ;;
        esac
    done
}
