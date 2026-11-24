#!/bin/bash
# multifon v2.3.3 — thin entrypoint (v2.3.3: UFW placement + dnscrypt-proxy toml + median/jitter health check, see docs/PHASES.md).
# All logic lives in lib/*.sh; this file only resolves its own directory,
# sources the modules, and starts the main menu.
# Run: ./multifon.sh  — or `multifon` after installing the command (menu 9).
#      ./multifon.sh fix        — run the checklist fixer without the menu.
#      ./multifon.sh install    — install the `multifon` command on PATH (no menu).
#      ./multifon.sh start-all  — start every instance unit (systemctl).
#      ./multifon.sh stop-all   — stop every instance unit.
#      ./multifon.sh status     — show every instance unit's state.
#      ./multifon.sh reapply-block — re-insert the scoped DNS/STUN block at the top of OUTPUT (boot-time unit + repair path).
# v2.3: instances are systemd units (one user + unit each, lib/systemd.sh).
# start.sh and start-psiphons.sh are gone.
# Existing behaviour is preserved: same folders (~/psiphon/psiphon-<cc>),
# same port registry (psiphon/.allocated_ports), same INFO.txt block format
# (keys changed: Unit/User/Sandbox — see lib/info.sh).

set -u

# Resolve BASH_SOURCE[0] through symlinks (v2.3.1 fix): the PATH install
# is a symlink (/usr/local/bin/multifon -> ~/multifon/multifon.sh), and
# plain dirname gives /usr/local/bin — so lib/ was not found and
# `multifon` only worked from inside ~/multifon. Follow the chain so
# MULTIFON_DIR is always the real checkout dir.
_MULTIFON_SRC="${BASH_SOURCE[0]}"
while [[ -L "$_MULTIFON_SRC" ]]; do
    _MULTIFON_SRC_DIR="$(cd -- "$(dirname -- "$_MULTIFON_SRC")" && pwd)"
    _MULTIFON_SRC="$(readlink "$_MULTIFON_SRC")"
    [[ "$_MULTIFON_SRC" != /* ]] && _MULTIFON_SRC="$_MULTIFON_SRC_DIR/$_MULTIFON_SRC"
done
MULTIFON_DIR="$(cd -- "$(dirname -- "$_MULTIFON_SRC")" && pwd)"
unset _MULTIFON_SRC _MULTIFON_SRC_DIR
MULTIFON_LIB_DIR="$MULTIFON_DIR/lib"

for _lib in common ports info psiphon systemd firewall doctor cores dns fixer menu; do
    # shellcheck source=/dev/null
    . "$MULTIFON_LIB_DIR/$_lib.sh"
done
unset _lib

case "${1:-}" in
    fix)         multifon_fix ;;
    install)     install_multifon_command ;;
    start-all)   systemd_start_all ;;
    stop-all)    systemd_stop_all ;;
    status)      systemd_units_status ;;
    repair-core) repair_instance_binaries ;;
    reapply-block)
        # Boot-time re-apply (multifon-firewall.service) + repair path:
        # iptables rules live only in the running firewall, so a reboot
        # or `ufw reload` wipes OUTPUT — this re-inserts the scoped
        # block at the top of OUTPUT. Idempotent; safe to run by hand.
        dns_leak_block_reapply ;;
    nuke)        multifon_nuke ;;
    "" )         main_loop ;;
    *)           echo "Usage: $0 [fix|install|start-all|stop-all|status|repair-core|reapply-block|nuke]" >&2
                 echo "  (no argument)  open the menu" >&2
                 echo "  fix            run the checklist fixer" >&2
                 echo "  install        install the \`multifon\` command on PATH" >&2
                 echo "  start-all      start every instance unit" >&2
                 echo "  stop-all       stop every instance unit" >&2
                 echo "  status         show every instance unit's state" >&2
                 echo "  repair-core    re-copy the verified core into every instance" >&2
                 echo "  reapply-block  re-insert the scoped DNS/STUN block at the top of OUTPUT" >&2
                 echo "  nuke           clean slate — delete everything multifon owns" >&2
                 exit 1 ;;
esac
