#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source /usr/local/lib/docker-lamp/runtime.sh

readonly MYSQL_SOCKET=/run/mysql/mysqld.sock
readonly MYSQL_DATADIR=/var/lib/mysql
readonly MYSQL_CONFIG=/run/mysql/docker-lamp.cnf
readonly MYSQL_INPUT=/run/mysql/mysql-init-input
readonly MYSQL_CLIENT_DEFAULTS=/run/mysql/mysql-bootstrap.cnf
readonly MYSQL_SQL=/run/mysql/mysql-bootstrap.sql
MYSQLD_PID=''

sql_string() { printf '%s' "$1" | sed "s/'/''/g"; }
sql_identifier() { printf '%s' "$1" | sed 's/`/``/g'; }
mysql_bootstrap() { mysql --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" "$@"; }

cleanup() {
    local status=$?
    if [[ -n "${MYSQLD_PID}" ]] && kill -0 "${MYSQLD_PID}" 2>/dev/null; then
        mysqladmin --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" shutdown >/dev/null 2>&1 \
            || kill -TERM "${MYSQLD_PID}" 2>/dev/null || true
        wait "${MYSQLD_PID}" 2>/dev/null || true
    fi
    rm -f "${MYSQL_INPUT}" "${MYSQL_CLIENT_DEFAULTS}" "${MYSQL_SQL}"
    exit "${status}"
}

wait_for_temporary_mysql() {
    local attempt
    for attempt in $(seq 1 60); do
        if mysqladmin --protocol=socket --socket="${MYSQL_SOCKET}" -uroot ping --silent >/dev/null 2>&1; then
            return 0
        fi
        kill -0 "${MYSQLD_PID}" 2>/dev/null || { wait "${MYSQLD_PID}"; return 1; }
        sleep 1
    done
    printf '%s\n' 'MySQL did not become ready within 60 seconds' >&2
    return 1
}

[[ -r "${MYSQL_INPUT}" ]] || { printf '%s\n' 'MySQL initialization input is missing' >&2; exit 1; }
# This file is generated with %q and has mode 0600. Source it as shell state,
# never export credentials into a child environment.
# shellcheck source=/dev/null
source "${MYSQL_INPUT}"
trap cleanup EXIT TERM INT
umask 077

printf '%s\n' 'Initializing MySQL data directory'
mysqld --defaults-file="${MYSQL_CONFIG}" --initialize-insecure --datadir="${MYSQL_DATADIR}"
printf '%s\n' 'Starting socket-only MySQL server for first-run setup'
mysqld --defaults-file="${MYSQL_CONFIG}" --datadir="${MYSQL_DATADIR}" --socket="${MYSQL_SOCKET}" \
    --pid-file=/run/mysql/mysqld-init.pid --skip-networking &
MYSQLD_PID=$!
wait_for_temporary_mysql

{
    printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$(sql_string "${ADMIN_PASSWORD}")"
    printf "DROP USER IF EXISTS ''@'localhost', ''@'%%', 'root'@'%%', 'root'@'::1';\n"
} > "${MYSQL_SQL}"
chmod 0600 "${MYSQL_SQL}"
mysql --protocol=socket --socket="${MYSQL_SOCKET}" -uroot < "${MYSQL_SQL}"
rm -f "${MYSQL_SQL}"

{
    printf '[client]\nuser=root\npassword=%s\nprotocol=socket\nsocket=%s\n' "${ADMIN_PASSWORD}" "${MYSQL_SOCKET}"
} > "${MYSQL_CLIENT_DEFAULTS}"
chmod 0600 "${MYSQL_CLIENT_DEFAULTS}"

{
    for host in localhost 127.0.0.1 ::1; do
        printf "CREATE USER 'admin'@'%s' IDENTIFIED BY '%s';\n" "${host}" "$(sql_string "${ADMIN_PASSWORD}")"
        printf "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%s' WITH GRANT OPTION;\n" "${host}"
    done
    if [[ "${APP_REQUESTED}" == 1 ]]; then
        printf 'CREATE DATABASE `%s`;\n' "$(sql_identifier "${APP_DATABASE}")"
        printf "CREATE USER '%s'@'%s' IDENTIFIED BY '%s';\n" \
            "$(sql_string "${APP_USER}")" "${ACCOUNT_HOST_POLICY}" "$(sql_string "${APP_PASSWORD}")"
        printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'%s';\n" \
            "$(sql_identifier "${APP_DATABASE}")" "$(sql_string "${APP_USER}")" "${ACCOUNT_HOST_POLICY}"
    fi
    printf 'FLUSH PRIVILEGES;\n'
} > "${MYSQL_SQL}"
chmod 0600 "${MYSQL_SQL}"
mysql_bootstrap < "${MYSQL_SQL}"
rm -f "${MYSQL_SQL}"

if [[ -d /docker-entrypoint-initdb.d ]]; then
    printf '%s\n' 'Running trusted initialization imports in lexical order'
    shopt -s nullglob
    while IFS= read -r -d '' import_file; do
        case "${import_file}" in
            *.sql) mysql_bootstrap < "${import_file}" ;;
            *.sql.gz) gzip -cd -- "${import_file}" | mysql_bootstrap ;;
            *)
                if [[ -x "${import_file}" && -f "${import_file}" ]]; then
                    MYSQL_INIT_DEFAULTS_FILE="${MYSQL_CLIENT_DEFAULTS}" "${import_file}"
                fi
                ;;
        esac
    done < <(LC_ALL=C printf '%s\0' /docker-entrypoint-initdb.d/* | LC_ALL=C sort -z)
    shopt -u nullglob
fi

mysqladmin --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" shutdown
wait "${MYSQLD_PID}"
MYSQLD_PID=''
mysql_write_state ready
printf '%s\n' 'MySQL initialization completed.'
