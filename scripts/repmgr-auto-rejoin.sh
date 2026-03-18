Create repmgr-auto-rejoin.sh for both nodes and configure REPMGR_CONN &CLONE_HOST vice-versa.

#!/bin/bash
set -uo pipefail

# ------------------ Logging & Lock ------------------ #
exec >> /var/log/repmgr-auto-rejoin.log 2>&1

LOCK_FILE="/tmp/repmgr-auto-rejoin.lock"
exec 200>$LOCK_FILE
flock -n 200 || {
  echo "[INFO] Another instance is already running. Exiting."
  exit 0
}

# ------------------ Configuration ------------------ #
REPMGR_CONF="/etc/postgresql/17/main/repmgr.conf"
REPMGR_CONN="host=DB02 user=repmgr dbname=repmgr connect_timeout=2"
PGDATA="/db/data"
CLONE_HOST="DB02"
ARCHIVE_DIR="/nfs/archive"
BACKUP_DIR="${PGDATA}_bak_$(date +%Y%m%d_%H%M%S)"
PGSERVICE="postgresql@17-main.service"

NODE_NAME=$(grep -E "^node_name" "$REPMGR_CONF" | awk -F= '{print $2}' | xargs)

# ------------------ Functions ------------------ #

wait_for_postgres_ready() {
  echo "[INFO] Waiting for PostgreSQL to finish recovery..."
  local timeout=900 # 15 minutes
  local elapsed=0

  while true; do
    if sudo -u postgres psql -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
      echo "[INFO] PostgreSQL is accepting queries."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed+5))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "[ERROR] PostgreSQL did not become ready within $timeout seconds."
      return 1
    fi
  done
}

get_cluster_status() {
  sudo -u postgres repmgr -f "$REPMGR_CONF" cluster show | awk -v node="$NODE_NAME" '
    BEGIN {FS="|"}
    $2 ~ node {gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}
  '
}

try_rejoin() {
  echo "[INFO] Attempting pg_rewind rejoin..."

  if systemctl is-active --quiet "$PGSERVICE"; then
    echo "[INFO] Stopping PostgreSQL before pg_rewind..."
    systemctl stop "$PGSERVICE"
  fi

  local attempt=1
  local max_attempts=10

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "[INFO] pg_rewind attempt #$attempt"

    # Capture exit code of rejoin
    set +e
    sudo -u postgres repmgr -f "$REPMGR_CONF" node rejoin -d "$REPMGR_CONN" --force-rewind --verbose
    local exit_code=$?
    set -e

    if [ $exit_code -eq 0 ]; then
      echo "[INFO] repmgr report success."
      break
    fi

    # Check if failure was just a missing WAL file
    missing_wal=$(sudo -u postgres /usr/lib/postgresql/17/bin/pg_rewind -D "$PGDATA" --source-server="$REPMGR_CONN" --dry-run 2>&1 | \
      grep "could not open file" | sed -E 's/.*pg_wal\/([^"]+)".*/\1/')

    if [ -n "$missing_wal" ]; then
      echo "[WARN] Missing WAL: $missing_wal. Restoring from archive..."
      archive_file="$ARCHIVE_DIR/$missing_wal.zst"
      if [ -f "$archive_file" ]; then
        sudo -u postgres zstd -d -f "$archive_file" -o "$PGDATA/pg_wal/$missing_wal"
        chown postgres:postgres "$PGDATA/pg_wal/$missing_wal"
        ((attempt++))
        continue
      fi
    fi

    echo "[INFO] Rejoin command finished/timed out. Checking if PG is recovering..."
    break
  done

  # CRITICAL: Even if repmgr failed, PG might be starting up fine.
  systemctl start "$PGSERVICE"
  if wait_for_postgres_ready; then
    sleep 10 # Give repmgrd a moment to update metadata
    local status=$(get_cluster_status)
    if [[ "$status" == "running" ]]; then
      echo "[SUCCESS] Node is active in cluster. No reclone needed."
      return 0
    fi
  fi

  echo "[ERROR] Node failed to reach 'running' status after rejoin attempt."
  return 1
}

do_clone() {
  echo "[WARN] Performing full reclone from $CLONE_HOST..."
  systemctl stop "$PGSERVICE" || true
  mv "$PGDATA" "$BACKUP_DIR"
  sudo -u postgres repmgr -f "$REPMGR_CONF" -h "$CLONE_HOST" -U repmgr -d repmgr standby clone -F
  systemctl start "$PGSERVICE"
  wait_for_postgres_ready || { echo "[ERROR] PG failed after clone"; exit 1; }
  sudo -u postgres repmgr -f "$REPMGR_CONF" standby register -F
  echo "[SUCCESS] Standby re-cloned and registered."
}

# ------------------ Main Logic ------------------ #

# 1. Check if node is already the Primary
is_primary=$(sudo -u postgres repmgr -f "$REPMGR_CONF" cluster show | awk -v node="$NODE_NAME" 'BEGIN {FS="|"} $2 ~ node && $3 ~ /primary/ {print "yes"}')
if [[ "${is_primary:-no}" == "yes" ]]; then
  echo "[INFO] Node '$NODE_NAME' is primary. No action needed."
  exit 0
fi

# 2. Check current status
node_status=$(get_cluster_status)
if [[ "$node_status" == "running" ]]; then
  echo "[INFO] Node '$NODE_NAME' is already active. Nothing to do."
  exit 0
fi

# 3. Try to rejoin (rewind) first
if try_rejoin; then
  exit 0
fi

# 4. Final Fallback
do_clone
exit 0
