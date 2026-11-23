#!/bin/bash
# multifon v2 — lib/info.sh
# INFO.txt registry: one "=== <name> ===" block per instance + a SYSTEM block.
# Format is unchanged from v1 so existing INFO.txt files keep working.
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
info_write() {
  local name="$1" cc="$2" dir="$3" http="$4" socks="$5"
  local bin start start_all files
  mkdir -p "$PSIPHON_BASE_DIR/psiphon"
  [ -f "$INFO_FILE" ] || : > "$INFO_FILE"

  bin="$dir/psiphon-tunnel-core-x86_64"
  start="$dir/start.sh"
  start_all="$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
  files=$(ls -1 "$dir" 2>/dev/null | sed 's/^/  - /')

  {
    echo "Folder: $dir"
    echo "Egress: $cc"
    echo "HTTP: $http"
    echo "SOCKS: $socks"
    echo "Binary: $bin"
    echo "StartScript: $start"
    echo "StartAllScript: $start_all"
    echo "Firejail: yes"
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

  local fj="no"; command -v firejail >/dev/null 2>&1 && fj="yes"
  local loc_count start_all autostart
  loc_count=$( find "$HOME/psiphon" -maxdepth 1 -type d -name "psiphon-*" 2>/dev/null | wc -l )
  start_all="$PSIPHON_BASE_DIR/psiphon/start-psiphons.sh"
  autostart="disabled"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled multifon-psiphon.service >/dev/null 2>&1; then
      autostart="enabled"
    elif systemctl is-active multifon-psiphon.service >/dev/null 2>&1; then
      autostart="active"
    fi
  fi

  {
    echo "PsiphonInstalled: $psi"
    echo "PsiphonBinary: $psi_path"
    echo "FirejailInstalled: $fj"
    echo "LocationsCount: $loc_count"
    echo "StartAllScript: $start_all"
    echo "AutostartService: multifon-psiphon.service ($autostart)"
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
        Folder:*|Egress:*|HTTP:*|SOCKS:*|Binary:*|StartScript:*|StartAllScript:*|Firejail:*|Date:*) echo "$line" >> "$tmp" ;;
        PsiphonInstalled:*|PsiphonBinary:*|FirejailInstalled:*|LocationsCount:*|AutostartService:*) echo "$line" >> "$tmp" ;;
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
