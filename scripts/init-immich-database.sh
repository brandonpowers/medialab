#!/bin/bash
# Initialize Immich database with vector extension
# Called automatically by PostgreSQL container on first startup

set -e
set -u

echo "Creating Immich database with vector extension..."

# Create immich database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE immich;
    GRANT ALL PRIVILEGES ON DATABASE immich TO $POSTGRES_USER;
EOSQL

# Enable vector extension for Immich AI/ML features
echo "Enabling pgvecto-rs extension for Immich..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "immich" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vectors;
EOSQL

echo "Immich database initialized successfully!"
