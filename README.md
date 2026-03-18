# 🔥 PostgreSQL 17 HA Cluster with repmgr + Keepalived (Self-Healing)

Production-grade High Availability setup using:

- PostgreSQL 17
- TimescaleDB
- repmgr
- Keepalived
- VIP-based routing
- Automated node recovery

---

## 🚀 Features

✅ Automatic failover  
✅ Zero application changes (VIP-based routing)  
✅ Automatic standby promotion  
✅ Self-healing failed node rejoin (pg_rewind + reclone)  
✅ WAL archiving with recovery support  
✅ Designed for high-ingestion workloads (20K+ inserts/sec)

---

## 🏗 Architecture

- Applications connect only via VIP
- Failover is transparent
- Replication via WAL streaming

---

## ⚡ Failover Flow

1. Primary crashes  
2. repmgr promotes standby  
3. Keepalived shifts VIP  
4. Applications reconnect automatically  

⏱ Failover time: ~5–6 seconds

---

## 🔄 Self-Healing Recovery

Automated recovery flow:

- Attempt pg_rewind rejoin
- Restore missing WAL from archive
- Fallback to full reclone

Handled via systemd timer every 1 minute.

---

## 📊 Performance

- Handles **20K+ inserts/sec**
- Optimized for time-series workloads using TimescaleDB
- Minimal replication lag
- ~99.9% uptime in production

---

## 📂 Project Structure

- `configs/` → All config files
- `scripts/` → Health checks + automation
- `systemd/` → Auto-rejoin services
- `docs/` → Full setup guide

---

## 🧪 Failover Testing
systemctl stop postgresql

✔ Standby promoted  
✔ VIP switched  
✔ No app impact  

---

## 💡 Key Learnings

High availability is not just failover:

- Recovery automation is critical
- WAL safety is essential
- Node rejoin must be automated

---

## 📬 Connect

If you’re working on PostgreSQL HA or scaling time-series workloads, feel free to connect or discuss improvements.
