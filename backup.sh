#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCES=(
    "/labops/data"
    # Add more source directories here; multi-source backups use each directory's name.
)
BACKUP_ROOT="/labops/backup"

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

if [[ "${#SOURCES[@]}" -eq 0 ]]; then
    echo "ERROR: Configure at least one source directory in SOURCES." >&2
    exit 1
fi

for dir in "$DAILY_DIR" "$WEEKLY_DIR" "$MONTHLY_DIR"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
done

LATEST_DAILY=$(find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)
DEST_DAILY="$DAILY_DIR/$DATE"

RSYNC_OPTS=(-a --delete --numeric-ids)

if [[ "${#SOURCES[@]}" -gt 1 ]]; then
    declare -A source_names=()
    for source in "${SOURCES[@]}"; do
        if [[ ! -d "$source" ]]; then
            echo "[$DATE $(date +%H:%M:%S)] ERROR: Source directory does not exist: $source" >> "$LOG_FILE"
            exit 1
        fi

        source_name=$(basename "$source")
        if [[ -n "${source_names[$source_name]:-}" ]]; then
            echo "[$DATE $(date +%H:%M:%S)] ERROR: Multiple source directories share the name '$source_name'." >> "$LOG_FILE"
            exit 1
        fi
        source_names[$source_name]=1
    done
else
    for source in "${SOURCES[@]}"; do
        if [[ ! -d "$source" ]]; then
            echo "[$DATE $(date +%H:%M:%S)] ERROR: Source directory does not exist: $source" >> "$LOG_FILE"
            exit 1
        fi
    done
fi

echo "[$DATE $(date +%H:%M:%S)] Starting daily backup..." >> "$LOG_FILE"
for source in "${SOURCES[@]}"; do
    source_name=$(basename "$source")
    destination="$DEST_DAILY"
    link_dest="$LATEST_DAILY"

    if [[ "${#SOURCES[@]}" -gt 1 ]]; then
        destination="$DEST_DAILY/$source_name"
        link_dest="$LATEST_DAILY/$source_name"
    fi

    source_rsync_opts=("${RSYNC_OPTS[@]}")
    if [[ -n "$LATEST_DAILY" && "$LATEST_DAILY" != "$DEST_DAILY" && -d "$link_dest" ]]; then
        source_rsync_opts+=(--link-dest="$link_dest")
    fi

    echo "[$DATE $(date +%H:%M:%S)] Backing up $source..." >> "$LOG_FILE"
    rsync "${source_rsync_opts[@]}" "$source/" "$destination/" >> "$LOG_FILE" 2>&1
done

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
