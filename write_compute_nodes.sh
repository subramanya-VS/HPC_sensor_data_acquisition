#!/usr/bin/env bash
# write_free_nodes.sh
# Writes the list of compute nodes reported as "free" by pbsnodes -l free
# Usage: ./write_free_nodes.sh [output-file]
set -euo pipefail

OUT_FILE="${1:-./free_nodes.txt}"

# check pbsnodes exists
if ! command -v pbsnodes >/dev/null 2>&1; then
  echo "[ERROR] pbsnodes command not found in PATH" >&2
  exit 2
fi

# gather free nodes (stderr silenced)
nodes_raw="$(pbsnodes -l free 2>/dev/null || true)"

# if nothing returned, write a timestamped comment and exit
if [[ -z "${nodes_raw//[[:space:]]/}" ]]; then
  printf "# No free nodes found at %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUT_FILE"
  echo "[INFO] No free nodes found. Wrote header to $OUT_FILE"
  exit 0
fi

# Normalize:
# - replace commas and any whitespace with newlines
# - remove blank lines
# - sort and unique
{
  echo "$nodes_raw" \
    | tr ', ' '\n' \
    | sed '/^[[:space:]]*$/d' \
    | grep -v '^free$'
  hostname
} | sort -u > "$OUT_FILE"


echo "[OK] Wrote $(wc -l < "$OUT_FILE") node(s) to: $OUT_FILE"
