#!/usr/bin/env bash
set -euo pipefail

SOURCE="/labops/data"
BACKUP_ROOT="/labops/labops-backup"

DAILY_DIR="$BACKUP_ROOT/daily"
WEEKLY_DIR="$BACKUP_ROOT/weekly"
MONTHLY_DIR="$BACKUP_ROOT/monthly"
LOG_FILE="$BACKUP_ROOT/backup.log"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%u)  # 1 = Monday, 7 = Sunday
DAY_OF_MONTH=$(date +%d) # 01 - 31

for dir in "$DAILY_DIR" "$WEEKLY_DIR" "$MONTHLY_DIR"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
done

LATEST_DAILY=$(find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)
DEST_DAILY="$DAILY_DIR/$DATE"

RSYNC_OPTS=(-a --delete --numeric-ids)
if [[ -n "$LATEST_DAILY" && "$LATEST_DAILY" != "$DEST_DAILY" ]]; then
    RSYNC_OPTS+=(--link-dest="$LATEST_DAILY")
fi

echo "[$DATE $(date +%H:%M:%S)] Starting daily backup..." >> "$LOG_FILE"
rsync "${RSYNC_OPTS[@]}" "$SOURCE/" "$DEST_DAILY/" >> "$LOG_FILE" 2>&1

# Weekly backup every Sunday (7)
if [[ "$DAY_OF_WEEK" -eq 7 ]]; then
    cp -al "$DEST_DAILY" "$WEEKLY_DIR/$DATE"
    echo "[$DATE] Created weekly snapshot." >> "$LOG_FILE"
fi

# Monthly backup on the 1st of the month
if [[ "$DAY_OF_MONTH" -eq "01" ]]; then
    cp -al "$DEST_DAILY" "$MONTHLY_DIR/$DATE"
    echo "[$DATE] Created monthly snapshot." >> "$LOG_FILE"
fi

# Keep only the newest snapshots by name; snapshot names use YYYY-MM-DD.
prune_snapshots() {
    local dir=$1
    local keep=$2
    local excess
    local i
    local -a snapshots=()

    mapfile -d '' -t snapshots < <(
        find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z
    )
    excess=$((${#snapshots[@]} - keep))

    for ((i = 0; i < excess; i++)); do
        rm -rf -- "${snapshots[i]}"
    done
}

prune_snapshots "$DAILY_DIR" "$KEEP_DAILY"
prune_snapshots "$WEEKLY_DIR" "$KEEP_WEEKLY"
prune_snapshots "$MONTHLY_DIR" "$KEEP_MONTHLY"

echo "[$DATE $(date +%H:%M:%S)] Backup finished." >> "$LOG_FILE"
