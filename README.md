# LabOps Backup Script

`backup.sh` creates dated, incremental snapshots of one or more source
directories. It is intended for a Linux system with Bash and `rsync` installed.

## Configuration

Edit the configuration near the top of `backup.sh` before running it:

```bash
SOURCES=(
    "/labops/data"
    "/labops/config"
)
BACKUP_ROOT="/labops/backup"
```

- Add every directory to back up to the `SOURCES` array. Use absolute paths.
- Set `BACKUP_ROOT` to the directory where snapshots and the log should be stored.
- Each source must exist and be readable by the user running the script.
- When multiple sources are configured, each is stored in a subdirectory named
  after its source directory. Source directories must have unique names (for
  example, `/srv/app/data` and `/srv/archive/data` cannot both be used because
  both are named `data`).
- With a single source, its contents are stored directly in each dated snapshot
  to preserve the original layout.

The script creates these directories under `BACKUP_ROOT`:

```text
daily/
weekly/
monthly/
backup.log
```

## How it works

1. The script syncs each source into a daily snapshot named `YYYY-MM-DD`.
   `rsync` preserves attributes and numeric ownership IDs. The `--delete`
   option removes files from the current daily snapshot when they have been
   removed from a source.
2. From the second daily run onward, unchanged files are hard-linked to the
   previous daily snapshot to save space. Changed files are copied.
3. On Sundays, it creates a weekly snapshot from that day's daily snapshot.
   On the first day of each month, it creates a monthly snapshot. These
   snapshots use hard links and therefore should remain under the same
   filesystem as the daily snapshots.
4. It retains the newest 7 daily, 4 weekly, and 6 monthly snapshots, deleting
   older snapshots.
5. Backup progress and `rsync` output are written to `BACKUP_ROOT/backup.log`.

The retention values can be changed with `KEEP_DAILY`, `KEEP_WEEKLY`, and
`KEEP_MONTHLY` near the top of the script.

## Run manually

Make the script executable, then run it:

```bash
chmod +x /path/to/backup.sh
/path/to/backup.sh
```

The account running it needs permission to read the source directories and
write to `BACKUP_ROOT`. Install `rsync` if it is not already available.

## Run daily at 19:00 with cron

1. Make sure the script is executable and has valid source and backup paths.
2. Open the crontab for the account that should run the backup:

   ```bash
   crontab -e
   ```

3. Add a line using the absolute path to the script:

   ```cron
   0 19 * * * /path/to/backup.sh
   ```

This runs the script every day at 19:00 according to the machine's local time.
The backup log is written to `BACKUP_ROOT/backup.log`. To also capture cron
errors and any output written to the terminal, use:

```cron
0 19 * * * /path/to/backup.sh >> /path/to/backup-cron.log 2>&1
```

Replace `/path/to/backup.sh` and `/path/to/backup-cron.log` with the actual
absolute paths. The cron account must have the same required source and backup
permissions as when running the script manually.
