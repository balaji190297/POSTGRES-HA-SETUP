
#!/bin/bash
set -euo pipefail

# ===== CONFIGURATION =====
ARCHIVE_DIR="/timescaledb/archive"  # WAL archive folder
PGUSER="postgres"
PGDATABASE="postgres"
PGHOST="/var/run/postgresql"
LOGFILE="/var/log/wal_archive_cleanup.log"

# ===== LOGGING =====
exec >> "$LOGFILE" 2>&1
echo "==== WAL Archive Cleanup started at $(date) ===="

# ===== FUNCTION =====
#compress_wal() {
#  local file="$1"
#  [[ "$file" == *.zst ]] && return
#  echo "[INFO] Compressing $file..."
#  zstd -19 "$file"
#}

# ===== 1. Determine oldest WAL needed =====
OLDEST_NEEDED=$(psql -U "$PGUSER" -d "$PGDATABASE" -h "$PGHOST" -t -A -c "
  SELECT restart_lsn
  FROM pg_replication_slots
  WHERE restart_lsn IS NOT NULL
  ORDER BY pg_lsn(restart_lsn)
  LIMIT 1;
" || echo "")

# If no active replication slot, use primary’s current WAL
if [[ -z "$OLDEST_NEEDED" ]]; then
  IS_PRIMARY=$(psql -U "$PGUSER" -d "$PGDATABASE" -h "$PGHOST" -t -A -c "SELECT pg_is_in_recovery();")
  if [[ "$IS_PRIMARY" == "f" ]]; then
    OLDEST_NEEDED=$(psql -U "$PGUSER" -d "$PGDATABASE" -h "$PGHOST" -t -A -c "SELECT pg_current_wal_lsn();")
  else
    echo "[WARN] Standby in recovery with no replication slots. Cannot determine WAL safely. Skipping cleanup."
    exit 0
  fi
fi

echo "[INFO] Oldest WAL needed: $OLDEST_NEEDED"

# ===== 2. Convert LSN to WAL file name =====
OLDEST_WAL=$(psql -U "$PGUSER" -d "$PGDATABASE" -h "$PGHOST" -t -A -c \
  "SELECT pg_walfile_name('$OLDEST_NEEDED'::pg_lsn);")

echo "[INFO] Oldest WAL file needed: $OLDEST_WAL"

# ===== 3. Run pg_archivecleanup =====
echo "[INFO] Running pg_archivecleanup..."
pg_archivecleanup -d -x .zst "$ARCHIVE_DIR" "$OLDEST_WAL"

echo "[SUCCESS] WAL archive cleanup completed at $(date)"


