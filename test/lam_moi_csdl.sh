#!/bin/bash
cd "$(dirname "$0")/.."
P="psql -h /tmp -U postgres -v ON_ERROR_STOP=1 -q"
psql -h /tmp -U postgres -qc "drop database if exists gara" -c "create database gara" >/dev/null 2>&1
for f in test/00_supabase_stub.sql supabase/migrations/[0-9]*.sql test/02_nguoi_dung_thu.sql; do
  $P -d gara -f $f 2>&1 | grep -v -E "NOTICE|^$" && echo "LỖI khi chạy $f"
done
echo "CSDL sẵn sàng"
