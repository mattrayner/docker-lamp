#!/usr/bin/env bash
set -euo pipefail

readonly MYSQL_SOCKET=/run/mysqld/mysqld.sock
readonly MYSQL_DATADIR=/var/lib/mysql
MYSQLD_PID=''

sql_string() { printf '%s' "$1" | sed "s/'/''/g"; }
sql_identifier() { printf '%s' "$1" | sed 's/`/``/g'; }
mysql_root() { mysql --protocol=socket --socket="${MYSQL_SOCKET}" -uroot "$@"; }

stop_temporary_mysql() {
    local status=$?
    if [[ -n "${MYSQLD_PID}" ]] && kill -0 "${MYSQLD_PID}" 2>/dev/null; then
        mysqladmin --protocol=socket --socket="${MYSQL_SOCKET}" -uroot shutdown >/dev/null 2>&1 || kill "${MYSQLD_PID}" 2>/dev/null || true
        wait "${MYSQLD_PID}" || true
    fi
    exit "${status}"
}

wait_for_temporary_mysql() {
    local attempt
    for attempt in $(seq 1 60); do
        if mysqladmin --protocol=socket --socket="${MYSQL_SOCKET}" -uroot ping --silent >/dev/null 2>&1; then
            return 0
        fi
        if ! kill -0 "${MYSQLD_PID}" 2>/dev/null; then
            wait "${MYSQLD_PID}"
            return 1
        fi
        sleep 1
    done
    echo "MySQL did not become ready within 60 seconds" >&2
    return 1
}

if [[ -d "${MYSQL_DATADIR}/mysql" ]]; then
    echo "MySQL data directory is already initialized; skipping initialization"
    exit 0
fi

echo "Initializing MySQL data directory"
mysqld --initialize-insecure --user=mysql --datadir="${MYSQL_DATADIR}"
echo "Starting temporary MySQL server for first-run setup"
mysqld --user=mysql --datadir="${MYSQL_DATADIR}" --socket="${MYSQL_SOCKET}" \
    --pid-file=/run/mysqld/mysqld-init.pid --skip-networking &
MYSQLD_PID=$!
trap stop_temporary_mysql EXIT
wait_for_temporary_mysql

admin_password="${MYSQL_ADMIN_PASS:-$(openssl rand -base64 24 | tr -d '\n')}"
mysql_root --execute "CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY '$(sql_string "${admin_password}")'"
mysql_root --execute "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION"

if [[ -n "${CREATE_MYSQL_BASIC_USER_AND_DB:-}" || -n "${MYSQL_USER_NAME:-}" || -n "${MYSQL_USER_DB:-}" || -n "${MYSQL_USER_PASS:-}" ]]; then
    basic_user="${MYSQL_USER_NAME:-user}"
    basic_database="${MYSQL_USER_DB:-db}"
    basic_password="${MYSQL_USER_PASS:-password}"
    mysql_root --execute "CREATE DATABASE IF NOT EXISTS \`$(sql_identifier "${basic_database}")\`"
    mysql_root --execute "CREATE USER IF NOT EXISTS '$(sql_string "${basic_user}")'@'%' IDENTIFIED BY '$(sql_string "${basic_password}")'"
    mysql_root --execute "GRANT ALL PRIVILEGES ON \`$(sql_identifier "${basic_database}")\`.* TO '$(sql_string "${basic_user}")'@'%'"
fi

if [[ -f /db/init.sql ]]; then
    echo "Running /db/init.sql"
    mysql_root < /db/init.sql
fi

echo "MySQL initialization completed; admin password: ${admin_password}"
mysqladmin --protocol=socket --socket="${MYSQL_SOCKET}" -uroot shutdown
wait "${MYSQLD_PID}"
MYSQLD_PID=''
trap - EXIT
