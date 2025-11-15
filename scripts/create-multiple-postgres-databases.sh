#!/bin/bash
# Create multiple PostgreSQL databases
# Usage: Set POSTGRES_MULTIPLE_DATABASES="db1,db2,db3" in environment

set -e
set -u

function create_user_and_database() {
    local database=$1
    echo "Creating database '$database'"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE DATABASE $database;
        GRANT ALL PRIVILEGES ON DATABASE $database TO $POSTGRES_USER;
EOSQL

    # Enable vector extension for Immich
    if [ "$database" = "immich" ]; then
        echo "Enabling vector extension for Immich"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$database" <<-EOSQL
            CREATE EXTENSION IF NOT EXISTS vectors;
EOSQL
    fi
}

if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    echo "Multiple database creation requested: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        create_user_and_database $db
    done
    echo "Multiple databases created"
fi
