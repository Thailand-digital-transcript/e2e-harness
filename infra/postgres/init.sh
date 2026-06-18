#!/usr/bin/env bash
set -e

# Create one database per service. The postgres image runs scripts in
# /docker-entrypoint-initdb.d/ as the POSTGRES_USER on startup.
for db in transcript_processing transcript_orchestrator transcript_signing \
          transcript_pdf_generation eidasremotesigning; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
        CREATE DATABASE $db;
SQL
    echo "Created database: $db"
done
