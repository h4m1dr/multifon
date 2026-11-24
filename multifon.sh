#!/bin/bash
# multifon v2.2 — thin entrypoint.
# All logic lives in lib/*.sh; this file only resolves its own directory,
# sources the modules, and starts the main menu.
# Run: ./multifon.sh  — or `multifon` after installing the command (menu 9).
#      ./multifon.sh fix  — run the checklist fixer without the menu.
# Existing behaviour is preserved: same folders (~/psiphon/psiphon-<cc>),
# same port registry (psiphon/.allocated_ports), same INFO.txt format.

set -u

MULTIFON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MULTIFON_LIB_DIR="$MULTIFON_DIR/lib"

for _lib in common ports info psiphon firewall doctor cores dns fixer menu; do
    # shellcheck source=/dev/null
    . "$MULTIFON_LIB_DIR/$_lib.sh"
done
unset _lib

case "${1:-}" in
    fix)   multifon_fix ;;
    "" )   main_loop ;;
    *)     echo "Usage: $0 [fix]" >&2; echo "  (no argument)  open the menu" >&2; echo "  fix            run the checklist fixer" >&2; exit 1 ;;
esac
