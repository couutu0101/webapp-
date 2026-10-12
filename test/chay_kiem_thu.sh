#!/bin/bash
# Tạo lại CSDL kiểm thử và chạy toàn bộ kiểm thử
cd "$(dirname "$0")/.."
P="psql -h /tmp -U postgres -v ON_ERROR_STOP=1 -q"
psql -h /tmp -U postgres -qc "drop database if exists gara" -c "create database gara" >/dev/null 2>&1
for f in test/00_supabase_stub.sql supabase/migrations/00*.sql; do
  $P -d gara -f $f 2>&1 | grep -v -E "NOTICE|^$" && { echo "LỖI khi chạy $f"; }
done
$P -d gara -f test/01_kiem_thu.sql 2>&1 | grep -v "^NOTICE"
