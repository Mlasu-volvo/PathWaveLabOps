#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCES=(
    "/labops/data"
    # Add more source directories here; multi-source backups use each directory's name.
)
BACKUP_ROOT="/labops/backup"
ERROR_EMAIL_RECIPIENTS=(
    # "name@example.com"
)

DAILY_DIR="$BACKUP_ROOT/daily"
WEEKLY_DIR="$BACKUP_ROOT/weekly"
MONTHLY_DIR="$BACKUP_ROOT/monthly"
LOG_FILE="$BACKUP_ROOT/backup.log"

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

send_error_email() {
    local status=$1
    local message=$2
    local line=$3
    local sendmail_path
    local recipient_header
    local host

    if [[ "${#ERROR_EMAIL_RECIPIENTS[@]}" -eq 0 ]]; then
        return 0
    fi

    if sendmail_path=$(command -v sendmail); then
        :
    elif [[ -x /usr/sbin/sendmail ]]; then
        sendmail_path=/usr/sbin/sendmail
    else
        printf '[%s] ERROR: Cannot send failure notification; sendmail was not found.\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE" 2>/dev/null || true
        return 0
    fi

    printf -v recipient_header '%s, ' "${ERROR_EMAIL_RECIPIENTS[@]}"
    recipient_header=${recipient_header%, }
    host=$(hostname 2>/dev/null || printf 'unknown host')

    if {
        printf 'To: %s\n' "$recipient_header"
        printf 'Subject: Backup failed on %s\n' "$host"
        printf 'Content-Type: text/plain; charset=UTF-8\n\n'
        printf 'The backup script failed on %s.\n' "$host"
        printf 'Date: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Exit status: %s\n' "$status"
        printf 'Line: %s\n' "$line"
        printf 'Error: %s\n' "$message"
    } | "$sendmail_path" -t 2>> "$LOG_FILE"; then
        :
    else
        printf '[%s] ERROR: Sending the failure notification email failed.\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

report_error() {
    local status=$1
    local message=$2
    local line=$3

    trap - ERR
    if ! printf '[%s] ERROR (exit %s, line %s): %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$status" "$line" "$message" >> "$LOG_FILE"; then
        printf 'Backup failed (exit %s, line %s): %s\n' "$status" "$line" "$message" >&2
    fi
    send_error_email "$status" "$message" "$line"
    exit "$status"
}

trap 'report_error "$?" "$BASH_COMMAND" "$LINENO"' ERR

DATE=$(date +%Y-%m-%d)
DAY_OF_WEEK=$(date +%u)  # 1 = Monday, 7 = Sunday
DAY_OF_MONTH=$(date +%d) # 01 - 31

if [[ "${#SOURCES[@]}" -eq 0 ]]; then
    report_error 1 "Configure at least one source directory in SOURCES." "$LINENO"
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
            report_error 1 "Source directory does not exist: $source" "$LINENO"
        fi

        source_name=$(basename "$source")
        if [[ -n "${source_names[$source_name]:-}" ]]; then
            report_error 1 "Multiple source directories share the name '$source_name'." "$LINENO"
        fi
        source_names[$source_name]=1
    done
else
    for source in "${SOURCES[@]}"; do
        if [[ ! -d "$source" ]]; then
            report_error 1 "Source directory does not exist: $source" "$LINENO"
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
