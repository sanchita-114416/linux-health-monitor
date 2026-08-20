# Linux Health Monitor

A dependency-free bash script that checks CPU load, memory, swap, and disk
usage against configurable thresholds, logs every check to a CSV history
file for trending, and sends a webhook alert (Slack/Teams) when something
crosses the line.

## Why

Most small/mid environments don't have a full Prometheus/Grafana stack
running on every box, but you still want to know *before* a disk fills up or
memory gets tight, not after a service falls over. This is the lightweight
version of that: a single script, a cron job, and a CSV file you can chart
whenever you want.

## What it does

- Reads 1-minute load average and expresses it as a percentage of available
  CPU cores.
- Reads memory and swap usage from `free`.
- Checks disk usage percentage for a configurable list of mount points and
  reports the fullest one.
- Appends every check to `history.csv` (timestamp, cpu, mem, swap, disk,
  worst mount, alert yes/no) so you can graph trends later in Excel/Sheets
  or feed it into something like Grafana.
- If any threshold is breached, logs to `alerts.log` and optionally POSTs a
  message to a Slack/Teams incoming webhook.

## Usage

```bash
cp config.env.example config.env   # edit thresholds + webhook URL
chmod +x health_monitor.sh
./health_monitor.sh
```

Run it on a schedule with cron:

```
*/5 * * * * /opt/health-monitor/health_monitor.sh >> /var/log/health-monitor/cron.log 2>&1
```

## Requirements

- bash, coreutils, `free`, `df`, `awk` (present on virtually every Linux box)
- `curl` only if you're using webhook alerts

