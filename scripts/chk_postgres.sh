chk_postgres.sh

#!/bin/bash
# Health check for Keepalived VIP in a PostgreSQL + repmgr cluster
# Works for both primary and standby nodes

set -e

# PostgreSQL / repmgr config
PG_OS_USER=postgres
PG_USER=repmgr
PG_PORT=5432
PG_DB=repmgr
REPMGR_CONF="/etc/postgresql/17/main/repmgr.conf"

# Detect host IP (or hardcode your primary interface IP)
PG_HOST=$(hostname -I | awk '{print $1}')

# --------------------------------------------
# 1️⃣ Check if PostgreSQL is accepting connections
# --------------------------------------------
sudo -u $PG_OS_USER pg_isready -h "$PG_HOST" -p $PG_PORT -U $PG_USER -d $PG_DB > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "PostgreSQL not ready"
    exit 1
fi

# --------------------------------------------
# 2️⃣ Check if this node is primary via pg_is_in_recovery()
# --------------------------------------------
IS_PRIMARY=$(sudo -u $PG_OS_USER psql -h "$PG_HOST" -p $PG_PORT -U $PG_USER -d $PG_DB -t -c "SELECT pg_is_in_recovery();")
IS_PRIMARY=$(echo "$IS_PRIMARY" | xargs)

# true = standby, false = primary
if [[ "$IS_PRIMARY" == "f" ]]; then
    NODE_ROLE="primary"
else
    NODE_ROLE="standby"
fi

# --------------------------------------------
# 3️⃣ Get actual primary node from repmgr cluster
# Only consider nodes that are primary AND running (*)
# --------------------------------------------
PRIMARY_NODE=$(sudo -u $PG_OS_USER repmgr -f "$REPMGR_CONF" cluster show \
    | awk -F'|' '$3 ~ /primary/ && $4 ~ /\*/ {print $2}' | xargs)

# Local hostname
NODE_NAME=$(hostname -s | xargs)

# Normalize names: strip domain suffix if present
NODE_NAME=${NODE_NAME%%.*}
PRIMARY_NODE=${PRIMARY_NODE%%.*}

# --------------------------------------------
# 4️⃣ Output and exit code
# --------------------------------------------
echo "NODE_ROLE=$NODE_ROLE, Primary node is $PRIMARY_NODE, current node is $NODE_NAME ($NODE_ROLE)"

if [[ "$NODE_NAME" == "$PRIMARY_NODE" ]]; then
    # Current node is primary
    exit 0
else
    # Current node is standby
    exit 1
fi
