#!/usr/bin/env bash
#
# health_monitor.sh
#
# Lightweight Linux server health check for CPU load, memory, disk, and swap
# usage. Designed to run from cron every few minutes. Writes every check to
# a CSV history file for trending, and fires an alert (webhook + local log)
# whenever a threshold is breached.
#
# Usage:
#   ./health_monitor.sh                # run one check using config.env
#   ./health_monitor.sh --once         # same as above, explicit
#
# Cron example (every 5 minutes):
#   */5 * * * * /opt/health-monitor/health_monitor.sh >> /var/log/health-monitor/cron.log 2>&1
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_DIR="/var/log/health-monitor"
CSV_FILE="${LOG_DIR}/history.csv"
ALERT_LOG="${LOG_DIR}/alerts.log"

# ---- defaults (overridden by config.env if present) ----
CPU_THRESHOLD=85       # % of 1-min load vs core count
MEM_THRESHOLD=90       # % memory used
DISK_THRESHOLD=85      # % disk used, checked per mount below
SWAP_THRESHOLD=50      # % swap used
DISK_MOUNTS="/ /var /home"
WEBHOOK_URL=""         # Slack/Teams incoming webhook URL, optional

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

mkdir -p "$LOG_DIR"
[[ -f "$CSV_FILE" ]] || echo "timestamp,cpu_pct,mem_pct,swap_pct,disk_worst_pct,disk_worst_mount,alert" > "$CSV_FILE"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

get_cpu_pct() {
  # 1-minute load average as a percentage of available cores
  local load cores
  load="$(cut -d' ' -f1 /proc/loadavg)"
  cores="$(nproc)"
  awk -v l="$load" -v c="$cores" 'BEGIN { printf "%.0f", (l / c) * 100 }'
}

get_mem_pct() {
  free | awk '/Mem:/ { printf "%.0f", ($2-$7)/$2 * 100 }'
}

get_swap_pct() {
  free | awk '/Swap:/ { if ($2 == 0) print 0; else printf "%.0f", $3/$2 * 100 }'
}

get_worst_disk() {
  # Prints "pct mount" for the fullest mount in DISK_MOUNTS
  local worst_pct=0 worst_mount="-"
  for m in $DISK_MOUNTS; do
    [[ -d "$m" ]] || continue
    local pct
    pct="$(df -P "$m" | awk 'NR==2 { gsub("%","",$5); print $5 }')"
    if (( pct > worst_pct )); then
      worst_pct=$pct
      worst_mount=$m
    fi
  done
  echo "${worst_pct} ${worst_mount}"
}

send_alert() {
  local message="$1"
  echo "[$(timestamp)] ALERT: ${message}" | tee -a "$ALERT_LOG"
  if [[ -n "$WEBHOOK_URL" ]]; then
    curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"text\": \"[$(hostname)] ${message}\"}" \
      "$WEBHOOK_URL" >/dev/null 2>&1 || \
      echo "[$(timestamp)] WARN: failed to deliver webhook alert" >> "$ALERT_LOG"
  fi
}

main() {
  local cpu mem swap disk_info disk_pct disk_mount alert_flag="no" reasons=()

  cpu="$(get_cpu_pct)"
  mem="$(get_mem_pct)"
  swap="$(get_swap_pct)"
  disk_info="$(get_worst_disk)"
  disk_pct="$(echo "$disk_info" | cut -d' ' -f1)"
  disk_mount="$(echo "$disk_info" | cut -d' ' -f2)"

  (( cpu >= CPU_THRESHOLD ))   && reasons+=("CPU ${cpu}% >= ${CPU_THRESHOLD}%")
  (( mem >= MEM_THRESHOLD ))   && reasons+=("Memory ${mem}% >= ${MEM_THRESHOLD}%")
  (( swap >= SWAP_THRESHOLD )) && reasons+=("Swap ${swap}% >= ${SWAP_THRESHOLD}%")
  (( disk_pct >= DISK_THRESHOLD )) && reasons+=("Disk ${disk_mount} ${disk_pct}% >= ${DISK_THRESHOLD}%")

  if (( ${#reasons[@]} > 0 )); then
    alert_flag="yes"
    send_alert "$(IFS='; '; echo "${reasons[*]}")"
  fi

  echo "$(timestamp),${cpu},${mem},${swap},${disk_pct},${disk_mount},${alert_flag}" >> "$CSV_FILE"
}

main "$@"
