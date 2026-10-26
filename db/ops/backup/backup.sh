#!/usr/bin/env bash
# Usage: DB_URL-style env vars -> PGHOST PGUSER PGDATABASE; PGPASSWORD must be set. Dumps go to ./dumps (not committed).
set -euo pipefail
mkdir -p dumps
pg_dump --format=custom --file="dumps/planetm-$(date +%Y%m%d-%H%M%S).dump" "${PGDATABASE:-planetm}"
