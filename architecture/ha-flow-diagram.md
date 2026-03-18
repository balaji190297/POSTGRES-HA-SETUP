🟢 NORMAL STATE

        Clients
           │
           ▼
      [ VIP - Keepalived ]
           │
           ▼
   ┌─────────────────────┐
   │  PRIMARY (DB01)     │  ← Writes
   │  PostgreSQL + TSDB  │
   └─────────┬───────────┘
             │  WAL Stream
             ▼
   ┌─────────────────────┐
   │  STANDBY (DB02)     │  ← Read/Replica
   │  PostgreSQL + TSDB  │
   └─────────────────────┘


⚡ FAILURE EVENT (Primary Crash)

❌ DB01 goes DOWN
   ↓
repmgr detects failure
   ↓
Standby promotion triggered
   ↓
DB02 → becomes PRIMARY


🔀 VIP SWITCH (Automatic)

Keepalived health check fails on DB01
   ↓
VIP released from DB01
   ↓
VIP assigned to DB02
   ↓
Clients reconnect automatically


🟢 NEW STATE (After Failover)

        Clients
           │
           ▼
      [ VIP - Keepalived ]
           │
           ▼
   ┌─────────────────────┐
   │  NEW PRIMARY (DB02) │  ← Writes continue
   └─────────┬───────────┘
             │
             ▼
     (Old primary recovering)


🔄 SELF-HEALING (Node Recovery)

DB01 comes back
   ↓
Auto rejoin script triggered
   ↓
pg_rewind attempt
   ↓
(if needed) WAL restore → reclone
   ↓
DB01 → becomes STANDBY again


🟢 FINAL STATE (Cluster Healthy Again)

   PRIMARY (DB02)  ⇄  STANDBY (DB01)
          │
          ▼
        VIP
          │
          ▼
       Clients
