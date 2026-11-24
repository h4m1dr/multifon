#!/bin/bash
# multifon v2.3 — thin entrypoint.
# All logic lives in lib/*.sh; this file only resolves its own directory,
# sources the modules, and starts the main menu.
# Run: ./multifon.sh  — or `multifon` after installing the command (menu 9).
#      ./multifon.sh fix        — run the checklist fixer without the menu.
#      ./multifon.sh start-all  — start every instance unit (systemctl).
#      ./multifon.sh stop-all   — stop every instance unit.
#      ./multifon.sh status     — show every instance unit's state.
# v2.3: instances are systemd units (one user + unit each, lib/systemd.sh).
# Firejail, start.sh and start-psiphons.sh are gone.
# Existing behaviour is preserved: same folders (~/psiphon/psiphon-<cc>),
# same port registry (psiphon/.allocated_ports), same INFO.txt block format
# (keys changed: Unit/User/Sandbox — see lib/info.sh).

set -u

MULTIFON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MULTIFON_LIB_DIR="$MULTIFON_DIR/lib"

for _lib in common ports info psiphon systemd firewall doctor cores dns fixer menu; do
    # shellcheck source=/dev/null
    . "$MULTIFON_LIB_DIR/$_lib.sh"
done
unset _lib

case "${1:-}" in
    fix)       multifon_fix ;;
    start-all) systemd_start_all ;;
    stop-all)  systemd_stop_all ;;
    status)    systemd_units_status ;;
    "" )       main_loop ;;
    *)         echo "Usage: $0 [fix|start-all|stop-all|status]" >&2
               echo "  (no argument)  open the menu" >&2
               echo "  fix            run the checklist fixer" >&2
               echo "  start-all      start every instance unit" >&2
               echo "  stop-all       stop every instance unit" >&2
               echo "  status         show every instance unit's state" >&2
               exit 1 ;;
esac
