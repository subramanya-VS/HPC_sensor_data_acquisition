#!/usr/bin/env bash
# get_ipmi_wide_nodes.sh
# Bash 3.2-compatible.
# For each compute node listed in free_nodes.txt, run:
#   ssh -tt <node> sudo ipmitool sdr list
# Collect CPU (%) and memory used/total (MB) and append them at the end of each CSV row.
# Output per-node CSVs under: BASE_DIR/YYYY-MM-DD/HH:00_to_HH+1:00/<node>.csv
set -euo pipefail

# -------- CONFIG (defaults) ----------
BASE_DIR="${BASE_DIR:-/var/log/ipmi_archive}"
TZ_NAME="${TZ_NAME:-Asia/Kolkata}"
NODES_FILE_DEFAULT="free_nodes.txt"
# -------------------------------------

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# sanitize header labels (remove commas/newlines/quotes)
sanitize() {
  local s="$1"
  s="${s//,/ _}"
  s="${s//$'\n'/ }"
  s="${s//\"/}"
  echo "$s"
}

# Process ipmitool output and append into CSV_FILE
# Now ALWAYS appends CPU (%), Memory Used (MB), Memory Total (MB) at the end.
# Arguments: ipmi_out_text, csv_file, cpu_pct, mem_used_mb, mem_total_mb
process_ipmi_output() {
  local ipmi_out="$1"
  local CSV_FILE="$2"
  local cpu_pct="${3:-}"
  local mem_used_mb="${4:-}"
  local mem_total_mb="${5:-}"

  local TMP
  TMP="$(mktemp /tmp/ipmi_readable.XXXXXX)" || return 1

  # parse ipmitool output into TMP (sensor|value|unit)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if echo "$line" | grep -iqE 'degrees|amps|volts|watts|rpm'; then
      sensor="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); print $1}')"
      field="$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
      num="$(echo "$field" | grep -oE '[0-9]+(\.[0-9]+)?' || true)"
      unit_raw="$(echo "$field" | grep -oEi 'degrees|amps|volts|watts|rpm' || true)"
      if [[ -n "$num" && -n "$unit_raw" ]]; then
        case "$(echo "$unit_raw" | tr '[:upper:]' '[:lower:]')" in
          "degrees"|"degrees c"|"degree c") u="C" ;;
          "amps") u="A" ;;
          "volts") u="V" ;;
          "watts") u="W" ;;
          "rpm") u="RPM" ;;
          *) u="$unit_raw" ;;
        esac
        printf '%s|%s|%s\n' "$sensor" "$num" "$u" >> "$TMP"
      fi
    fi
  done <<< "$ipmi_out"

  # If TMP has data: stable sort & dedupe. If empty, continue (we still want CPU/mem columns).
  if [[ -s "$TMP" ]]; then
    sort -f "$TMP" -o "$TMP"
    awk -F'|' '!seen[$1]++' "$TMP" > "${TMP}.uniq" && mv "${TMP}.uniq" "$TMP"
  fi

  # read into arrays (if TMP empty, arrays remain empty)
  sensors=(); values=(); units=()
  if [[ -s "$TMP" ]]; then
    while IFS='|' read -r s v u; do
      sensors+=("$s")
      values+=("$v")
      units+=("$u")
    done < "$TMP"
  fi

  # Build header: start with timestamp, then all sensors (if any), then the CPU/mem columns
  new_header="timestamp"
  i=0
  while [[ $i -lt ${#sensors[@]} ]]; do
    s="$(sanitize "${sensors[$i]}")"
    u="${units[$i]}"
    new_header="${new_header},${s} (${u})"
    i=$((i + 1))
  done

  # Append CPU/memory header columns (no extra spaces)
  new_header="${new_header},CPU (%),Memory Used (MB),Memory Total (MB)"

  # Check existing header
  need_new_file=1
  if [[ -f "$CSV_FILE" && -s "$CSV_FILE" ]]; then
    existing_header="$(head -n 1 "$CSV_FILE" | tr -d '\r')"
    if [[ "$existing_header" == "$new_header" ]]; then
      need_new_file=0
    else
      need_new_file=1
    fi
  else
    need_new_file=1
  fi

  # backup old CSV if header differs
  if [[ $need_new_file -eq 1 && -f "$CSV_FILE" && -s "$CSV_FILE" ]]; then
    bak="${CSV_FILE}.$(date -u +%Y%m%dT%H%M%SZ).bak"
    mv "$CSV_FILE" "$bak"
    echo "[INFO] Existing CSV header differs for $CSV_FILE. Backed up old CSV to: $bak"
  fi

  # write header if missing
  if [[ ! -f "$CSV_FILE" || ! -s "$CSV_FILE" ]]; then
    mkdir -p "$(dirname "$CSV_FILE")"
    echo "$new_header" > "$CSV_FILE"
  fi

  # Build row: timestamp, sensor values (if any) then cpu and mem values
  TS="$(timestamp)"
  row="${TS}"
  i=0
  while [[ $i -lt ${#values[@]} ]]; do
    v="${values[$i]//,/}"   # remove commas in values
    row="${row},${v}"
    i=$((i + 1))
  done

  # Append cpu and memory; if missing, leave blank fields
  if [[ -n "${cpu_pct:-}" ]]; then
    row="${row},${cpu_pct}"
  else
    row="${row},"
  fi
  if [[ -n "${mem_used_mb:-}" ]]; then
    row="${row},${mem_used_mb}"
  else
    row="${row},"
  fi
  if [[ -n "${mem_total_mb:-}" ]]; then
    row="${row},${mem_total_mb}"
  else
    row="${row},"
  fi

  echo "$row" >> "$CSV_FILE"
  echo "[OK] Appended readable sensors + CPU/mem to: $CSV_FILE"

  rm -f "$TMP"
  return 0
}

# -----------------------
# CLI args: allow overrides
# -----------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-dir)
      BASE_DIR="$2"; shift 2 ;;
    --base-dir=*)
      BASE_DIR="${1#*=}"; shift ;;
    --tz)
      TZ_NAME="$2"; shift 2 ;;
    --tz=*)
      TZ_NAME="${1#*=}"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--base-dir /path] [--tz Timezone] [nodes_file]
Defaults:
  BASE_DIR = $BASE_DIR
  TZ       = $TZ_NAME
nodes_file default: $NODES_FILE_DEFAULT
EOF
      exit 0 ;;
    *)
      NODES_FILE="$1"; shift ;;
  esac
done

if [[ -z "${NODES_FILE:-}" ]]; then
  NODES_FILE="$NODES_FILE_DEFAULT"
fi

export TZ="$TZ_NAME"

# -----------------------
# Read nodes file (portable)
# -----------------------
if [[ ! -f "$NODES_FILE" ]]; then
  echo "[ERROR] Nodes file not found: $NODES_FILE"
  exit 1
fi

nodes=()
while IFS= read -r line || [[ -n $line ]]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  case "$line" in
    \#*) continue ;;
  esac
  nodes+=("$line")
done < "$NODES_FILE"

if [[ "${#nodes[@]}" -eq 0 ]]; then
  echo "[ERROR] No nodes found in $NODES_FILE"
  exit 1
fi

# -----------------------
# Iterate nodes
# -----------------------
for node in "${nodes[@]}"; do
  echo "[INFO] Querying node: $node"

  # --- initialize IPMI_OUT so 'set -u' won't crash if ssh fails ---
  IPMI_OUT=""

  # Run ipmitool remotely via ssh; capture output (suppress ssh errors to continue)
  # -tt as requested; if you get weird chars, try -t or remove it.
  IPMI_OUT="$(ssh -tt "$node" sudo ipmitool sdr list 2>/dev/null || true)"

  # Collect CPU (%) and memory from remote host in a single ssh (memUsed = MemTotal - MemFree)
  CPU_MEM_OUT="$(ssh "$node" 'bash -s' <<'REMOTE' 2>/dev/null || true
# sample /proc/stat twice to compute CPU usage
read cpu user nice system idle iowait irq softirq steal < /proc/stat
total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle1=$((idle + iowait))
sleep 0.5
read cpu user nice system idle iowait irq softirq steal < /proc/stat
total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle2=$((idle + iowait))
cpu_usage=$(awk -v t1=$total1 -v t2=$total2 -v i1=$idle1 -v i2=$idle2 'BEGIN{ if (t2>t1) printf "%.1f", (1-(i2-i1)/(t2-t1))*100; else printf "0.0" }')

# read memory numbers from /proc/meminfo
mem_total_kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
mem_free_kb=$(awk '/^MemFree:/ {print $2; exit}' /proc/meminfo)

# default missing values to 0 to avoid arithmetic errors
mem_total_kb=${mem_total_kb:-0}
mem_free_kb=${mem_free_kb:-0}

# compute used = total - free (as requested)
mem_used_kb=$(( mem_total_kb - mem_free_kb ))
if [ "$mem_used_kb" -lt 0 ]; then mem_used_kb=0; fi

printf "%s|%s|%s\n" "$cpu_usage" "$mem_used_kb" "$mem_total_kb"
REMOTE
)" || true

  # Parse CPU_MEM_OUT
  cpu_pct=""
  mem_used_mb=""
  mem_total_mb=""
  if [[ -n "$CPU_MEM_OUT" ]]; then
    # expected format: cpu|used_kb|total_kb
    IFS='|' read -r cpu_val mem_used_kb mem_total_kb <<EOF
$CPU_MEM_OUT
EOF
    # convert kB to MB (integer MB)
    if [[ -n "${mem_used_kb:-}" ]]; then
      mem_used_mb=$(( mem_used_kb / 1024 ))
    fi
    if [[ -n "${mem_total_kb:-}" ]]; then
      mem_total_mb=$(( mem_total_kb / 1024 ))
    fi
    cpu_pct="$cpu_val"
  else
    echo "[WARN] Failed to collect CPU/memory info for $node"
  fi

  # Build destination dir using local TZ
  date_dir="$(date +%F)"
  start_hour="$(date +%H)"
  # compute next hour modulo 24 (avoid octal with 10#$)
  next_hour=$(( (10#$start_hour + 1) % 24 ))
  start_h_padded="$(printf '%02d' "$start_hour")"
  next_h_padded="$(printf '%02d' "$next_hour")"
  hour_dir="${start_h_padded}:00_to_${next_h_padded}:00"

  dest_dir="${BASE_DIR}/${date_dir}/${hour_dir}"
  mkdir -p "$dest_dir"

  # sanitize node name for filename
  node_safe="$(echo "$node" | sed 's/[\/[:space:]]/_/g')"
  CSV_FILE="${dest_dir}/${node_safe}.csv"

  # Call process_ipmi_output with appended cpu/mem values
  process_ipmi_output "${IPMI_OUT:-}" "$CSV_FILE" "$cpu_pct" "$mem_used_mb" "$mem_total_mb" || echo "[ERROR] Failed processing for $node"
done

echo "[DONE] All nodes processed."