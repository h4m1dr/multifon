#!/bin/bash
# multifon v2 — lib/info.sh
# INFO.txt registry: one "=== <name> ===" block per instance + a SYSTEM block.
# Block format is unchanged from v1 (=== NAME === / key: value lines), but
# v2.3 changed the KEYS: per-location StartScript/StartAllScript/Firejail
# are replaced by Unit/User/Sandbox (systemd), and the SYSTEM block's
# FirejailInstalled/StartAllScript/AutostartService by Sandbox/Units.
# validate_info_file below prunes the old keys on the next run.
# Sourced by multifon.sh; never run directly.

[[ -n "${_MULTIFON_INFO_LOADED:-}" ]] && return 0
_MULTIFON_INFO_LOADED=1

INFO_FILE="$PSIPHON_BASE_DIR/psiphon/INFO.txt"

# Internal helper: atomically replace a named block inside INFO_FILE.
# Usage: { echo "KEY: value"; ... } | _safe_replace_block "LABEL"
_safe_replace_block() {
  local label="$1"
  local tmp
  tmp=$(mktemp) || return 1

  mkdir -p "$PSIPHON_BASE_DIR/psiphon"
  [ -f "$INFO_FILE" ] || : > "$INFO_FILE"

  (
    # Lock the INFO file for exclusive update
    flock -w 3 9 || { rm -f "$tmp"; return 0; }

    # Copy INFO to tmp, skipping existing block for this label
    awk -v label="$label" '
      BEGIN { inblk=0 }
      $0==("=== "label" ===") { inblk=1; next }
      $0==("=== END "label" ===") { inblk=0; next }
      !inblk { print }
    ' "$INFO_FILE" > "$tmp"

    # Append new block content from stdin
    {
      printf '=== %s ===\n' "$label"
      cat
      printf '=== END %s ===\n\n' "$label"
    } >> "$tmp"

    # Atomic replace
    mv "$tmp" "$INFO_FILE"
  ) 9>>"$INFO_FILE"
}

# Remove one named block from INFO_FILE (no-op if absent).
# This is the single canonical removal used by delete + doctor, so a
# removed instance can never leave a stale INFO block behind (bug #1/#6).
info_remove_block() {
  local label="$1"
  local tmp
  [ -f "$INFO_FILE" ] || return 0
  tmp=$(mktemp) || return 1
  awk -v label="$label" '
    BEGIN { inblk=0 }
    $0==("=== "label" ===") { inblk=1; next }
    $0==("=== END "label" ===") { inblk=0; next }
    !inblk { print }
  ' "$INFO_FILE" > "$tmp" && mv "$tmp" "$INFO_FILE"
}

# List instance names that have an INFO block (one per line, no SYSTEM).
info_list_blocks() {
  [ -f "$INFO_FILE" ] || return 0
  grep -E '^=== [^ ]+ ===$' "$INFO_FILE" 2>/dev/null \
    | sed -E 's/^=== ([^ ]+) ===$/\1/' \
    | grep -v '^SYSTEM$' || true
}

# Write/refresh a LOCATION block (one per psiphon-XX folder)
# v2.3: Unit/User/Sandbox replace the old StartScript/StartAllScript/
# Firejail keys (no start.sh, no start-psiphons.sh, no Firejail any more).
info_write() {
  local name="$1" cc="$2" dir="$3" http="$4" socks="$5"
  local bin unit user files
  mkdir -p "$PSIPHON_BASE_DIR/psiphon"
  [ -f "$INFO_FILE" ] || : > "$INFO_FILE"

  bin="$dir/psiphon-tunnel-core-x86_64"
  unit=$(systemd_unit_name "$dir")
  user=$(systemd_instance_user "$dir")
  files=$(ls -1 "$dir" 2>/dev/null | sed 's/^/  - /')

  {
    echo "Folder: $dir"
    echo "Egress: $cc"
    echo "HTTP: $http"
    echo "SOCKS: $socks"
    echo "Binary: $bin"
    echo "Unit: $unit"
    echo "User: $user"
    echo "Sandbox: systemd"
    echo "Files:"
    [ -n "$files" ] && echo "$files"
    echo "Date: $(date -Is)"
  } | _safe_replace_block "$name"
}

# Write/refresh the SYSTEM overview block (no recursion)
info_write_system() {
  mkdir -p "$PSIPHON_BASE_DIR/psiphon"; [ -f "$INFO_FILE" ] || : > "$INFO_FILE"

  local psi="no" psi_path=""
  if [[ -x "/usr/bin/psiphon" ]]; then
    psi="yes"; psi_path="/usr/bin/psiphon"
  elif [[ -x "/usr/bin/psiphon-tunnel-core-x86_64" ]]; then
    psi="yes"; psi_path="/usr/bin/psiphon-tunnel-core-x86_64"
  fi

  local loc_count units
  loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )
  units=""
  if command -v systemctl >/dev/null 2>&1; then
    units=$(systemd_units_summary 2>/dev/null || true)
  fi

  {
    echo "PsiphonInstalled: $psi"
    echo "PsiphonBinary: $psi_path"
    echo "Sandbox: systemd"
    echo "LocationsCount: $loc_count"
    echo "Units: ${units:-none}"
    echo "Date: $(date -Is)"
  } | _safe_replace_block "SYSTEM"
}

# Validate/clean INFO file. Permissive for SYSTEM keys and Files list lines.
validate_info_file() {
  local tmp; tmp=$(mktemp) || return 1
  if [ -f "$INFO_FILE" ]; then
    while IFS= read -r line; do
      case "$line" in
        # Block markers
        '=== '*" ==="|"=== END "*" ===") echo "$line" >> "$tmp" ;;
        # Common keys (locations + system)
        Folder:*|Egress:*|HTTP:*|SOCKS:*|Binary:*|Unit:*|User:*|Sandbox:*|Date:*) echo "$line" >> "$tmp" ;;
        PsiphonInstalled:*|PsiphonBinary:*|Sandbox:*|LocationsCount:*|Units:*) echo "$line" >> "$tmp" ;;
        Files:*) echo "$line" >> "$tmp" ;;
        '  - '*) echo "$line" >> "$tmp" ;;
        # Preserve empty lines between blocks
        "") echo >> "$tmp" ;;
        # Drop anything else silently (avoid noisy logs)
        *) ;;
      esac
    done < "$INFO_FILE"
    mv "$tmp" "$INFO_FILE"
  else
    : > "$INFO_FILE"
  fi
}
