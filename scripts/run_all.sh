#!/usr/bin/env bash
# Rebuilds the whole warehouse from the raw CSV files:
#   schemas -> staging (python COPY) -> reconciled layer -> star schema -> quality checks
# Usage: scripts/run_all.sh          (env DATABASE_URL / PGDATABASE optional, default olist_dw)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
DB="${PGDATABASE:-olist_dw}"

psql -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 || createdb "$DB"
PSQL="psql -d $DB -v ON_ERROR_STOP=1 -q"

echo "== schemas";                 $PSQL -f sql/00_schemas.sql
echo "== staging (raw CSV copy)";  DATABASE_URL="dbname=$DB" uv run scripts/load_staging.py
for f in sql/2*.sql sql/3*.sql sql/4*.sql sql/5*.sql sql/6*.sql; do
  [ -e "$f" ] || continue
  echo "== $f"; $PSQL -f "$f"
done
echo "== done"
