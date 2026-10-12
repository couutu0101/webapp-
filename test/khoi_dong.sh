#!/bin/bash
# Khởi động môi trường thử: PostgreSQL 16 (socket /tmp) + máy chủ giả Supabase cổng 8765
cd "$(dirname "$0")"
PGBIN=/usr/lib/postgresql/16/bin
if ! pg_isready -h /tmp -q; then
  if [ ! -f /tmp/pgdata/PG_VERSION ]; then
    mkdir -p /tmp/pgdata && chown postgres /tmp/pgdata
    su postgres -c "$PGBIN/initdb -D /tmp/pgdata -U postgres -A trust" >/dev/null
  fi
  rm -f /tmp/pgdata/postmaster.pid
  su postgres -c "$PGBIN/pg_ctl -D /tmp/pgdata -l /tmp/pg.log -o '-k /tmp' -w start" >/dev/null
fi
pg_isready -h /tmp
if ! curl -s -o /dev/null localhost:8765/; then
  nohup python3 may_chu_thu.py 8765 > /tmp/mct.log 2>&1 &
  echo $! > /tmp/mct.pid
  sleep 1
fi
curl -s -o /dev/null -w "máy chủ thử: %{http_code}\n" localhost:8765/
