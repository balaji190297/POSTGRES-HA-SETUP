notify.sh

#!/bin/bash
# Keepalived notification script

TYPE=$1
NAME=$2
STATE=$3

LOGFILE="/var/log/keepalived-vip.log"
PG_OS_USER=postgres
PG_HOST=$(hostname -I | awk '{print $1}')
#PG_HOST=192.168.4.220
PG_PORT=5432
PG_USER=repmgr
PG_DB=repmgr
REPMGR_CONF="/etc/postgresql/17/main/repmgr.conf"

# Function to log cluster status
get_cluster_status() {
    echo "Cluster status at $(date '+%F %T'):" >> $LOGFILE
    sudo -u $PG_OS_USER repmgr -h $PG_HOST -f $REPMGR_CONF cluster show >> $LOGFILE
    echo "----------------------------------------" >> $LOGFILE
}

case $STATE in
    MASTER)
        echo "$(date '+%F %T') - ${NAME} is now MASTER on $(hostname)" >> $LOGFILE
        get_cluster_status
        ;;
    BACKUP)
        echo "$(date '+%F %T') - ${NAME} is now BACKUP on $(hostname)" >> $LOGFILE
        get_cluster_status
        ;;
    FAULT)
        echo "$(date '+%F %T') - ${NAME} entered FAULT state on $(hostname)" >> $LOGFILE
        get_cluster_status
        ;;
    *)
        echo "$(date '+%F %T') - ${NAME} unknown state ${STATE} on $(hostname)" >> $LOGFILE
        get_cluster_status
        ;;
esac
