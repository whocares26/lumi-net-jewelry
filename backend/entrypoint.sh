#!/bin/sh
# Generate Drogon config from environment variables
cat > /app/config.json << CFG
{
  "listeners": [{ "address": "0.0.0.0", "port": 8080 }],
  "db_clients": [{
    "rdbms":             "postgresql",
    "host":              "${DB_HOST:-db}",
    "port":              ${DB_PORT:-5432},
    "dbname":            "${DB_NAME:-lumidb}",
    "user":              "${DB_USER:-lumi}",
    "passwd":            "${DB_PASS:-lumipass}",
    "connection_number": 10
  }],
  "app": {
    "number_of_threads": 4,
    "run_as_daemon": false,
    "log_level": "DEBUG"
  }
}
CFG
exec /app/lumi_backend
