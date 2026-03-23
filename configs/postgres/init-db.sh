#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE microservices_dev;
    CREATE DATABASE microservices;
    CREATE USER app_user WITH PASSWORD '${APP_USER_PASSWORD:-dev-password-change-me}';
    GRANT ALL PRIVILEGES ON DATABASE microservices_dev TO app_user;
    GRANT ALL PRIVILEGES ON DATABASE microservices TO app_user;
EOSQL
for db in microservices_dev microservices; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d "$db" <<-EOSQL
        GRANT ALL ON SCHEMA public TO app_user;
EOSQL
done
