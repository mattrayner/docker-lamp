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
readonly MYSQL_MANIFEST=/run/mysql/import-manifest
MYSQLD_PID=''
IMPORT_CLIENT_PID=''
IMPORT_DECOMPRESS_PID=''
IMPORT_FIFO=''

mysql_bootstrap() { mysql --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" "$@"; }

cleanup() {
    local status=$?
    local deadline
    for pid in "${IMPORT_CLIENT_PID}" "${IMPORT_DECOMPRESS_PID}"; do
        [[ -n "${pid}" ]] && kill -TERM "${pid}" 2>/dev/null || true
    done
    if [[ -n "${IMPORT_CLIENT_PID}${IMPORT_DECOMPRESS_PID}" ]]; then
        deadline=$((SECONDS + 5))
        while { { [[ -n "${IMPORT_CLIENT_PID}" ]] && kill -0 "${IMPORT_CLIENT_PID}" 2>/dev/null; } \
            || { [[ -n "${IMPORT_DECOMPRESS_PID}" ]] && kill -0 "${IMPORT_DECOMPRESS_PID}" 2>/dev/null; }; } \
            && (( SECONDS < deadline )); do sleep 1; done
        for pid in "${IMPORT_CLIENT_PID}" "${IMPORT_DECOMPRESS_PID}"; do
            [[ -n "${pid}" ]] && kill -KILL "${pid}" 2>/dev/null || true
            [[ -n "${pid}" ]] && wait "${pid}" 2>/dev/null || true
        done
    fi
    IMPORT_CLIENT_PID=''
    IMPORT_DECOMPRESS_PID=''
    rm -f "${IMPORT_FIFO}"
    IMPORT_FIFO=''
    if [[ -n "${MYSQLD_PID}" ]] && kill -0 "${MYSQLD_PID}" 2>/dev/null; then
        timeout --kill-after=1s 10s mysqladmin --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" shutdown >/dev/null 2>&1 \
            || kill -TERM "${MYSQLD_PID}" 2>/dev/null || true
        deadline=$((SECONDS + 20))
        while kill -0 "${MYSQLD_PID}" 2>/dev/null && (( SECONDS < deadline )); do sleep 1; done
        if kill -0 "${MYSQLD_PID}" 2>/dev/null; then
            printf '%s\n' 'MySQL temporary initialization server did not stop within 20 seconds; forcing termination.' >&2
            kill -KILL "${MYSQLD_PID}" 2>/dev/null || true
        fi
        wait "${MYSQLD_PID}" 2>/dev/null || true
    fi
    rm -f "${MYSQL_INPUT}" "${MYSQL_CLIENT_DEFAULTS}" "${MYSQL_SQL}" "${MYSQL_MANIFEST}"
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

[[ -r "${MYSQL_INPUT}" && -r "${MYSQL_MANIFEST}" ]] || { printf '%s\n' 'MySQL initialization preflight data is missing' >&2; exit 1; }
# This file is generated with %q and has mode 0600. Source it as shell state,
# never export credentials into a child environment.
# shellcheck source=/dev/null
source "${MYSQL_INPUT}"
trap cleanup EXIT
trap 'exit 1' TERM INT
umask 077

printf '%s\n' 'Initializing MySQL data directory'
mysqld --defaults-file="${MYSQL_CONFIG}" --initialize-insecure --datadir="${MYSQL_DATADIR}"
printf '%s\n' 'Starting socket-only MySQL server for first-run setup'
mysqld --defaults-file="${MYSQL_CONFIG}" --datadir="${MYSQL_DATADIR}" --socket="${MYSQL_SOCKET}" \
    --pid-file=/run/mysql/mysqld-init.pid --skip-networking &
MYSQLD_PID=$!
wait_for_temporary_mysql

{
    printf "ALTER USER 'root'@'localhost' IDENTIFIED BY %s;\n" "$(mysql_sql_literal "${ADMIN_PASSWORD}")"
    printf "DROP USER IF EXISTS ''@'localhost', ''@'%%', 'root'@'%%', 'root'@'::1';\n"
} > "${MYSQL_SQL}"
chmod 0600 "${MYSQL_SQL}"
mysql --protocol=socket --socket="${MYSQL_SOCKET}" -uroot < "${MYSQL_SQL}"
rm -f "${MYSQL_SQL}"

{
    printf '[client]\nuser=root\npassword=%s\nprotocol=socket\nsocket=%s\n' "$(mysql_defaults_value "${ADMIN_PASSWORD}")" "${MYSQL_SOCKET}"
} > "${MYSQL_CLIENT_DEFAULTS}"
chmod 0600 "${MYSQL_CLIENT_DEFAULTS}"

{
    for host in localhost 127.0.0.1 ::1; do
        printf "CREATE USER %s@%s IDENTIFIED BY %s;\n" \
            "$(mysql_sql_literal admin)" "$(mysql_sql_literal "${host}")" "$(mysql_sql_literal "${ADMIN_PASSWORD}")"
        printf "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%s' WITH GRANT OPTION;\n" "${host}"
    done
    if [[ "${APP_REQUESTED}" == 1 ]]; then
        printf 'CREATE DATABASE `%s`;\n' "${APP_DATABASE//\`/\`\`}"
        printf "CREATE USER %s@%s IDENTIFIED BY %s;\n" \
            "$(mysql_sql_literal "${APP_USER}")" "$(mysql_sql_literal "${ACCOUNT_HOST_POLICY}")" "$(mysql_sql_literal "${APP_PASSWORD}")"
        printf "GRANT ALL PRIVILEGES ON %s TO %s@%s;\n" \
            "$(mysql_grant_database_target "${APP_DATABASE}")" "$(mysql_sql_literal "${APP_USER}")" "$(mysql_sql_literal "${ACCOUNT_HOST_POLICY}")"
    fi
    printf "ALTER USER 'root'@'localhost' ACCOUNT LOCK;\n"
    printf 'FLUSH PRIVILEGES;\n'
} > "${MYSQL_SQL}"
chmod 0600 "${MYSQL_SQL}"
mysql_bootstrap < "${MYSQL_SQL}"
rm -f "${MYSQL_SQL}"
{
    printf '[client]\nuser=admin\npassword=%s\nprotocol=socket\nsocket=%s\n' "$(mysql_defaults_value "${ADMIN_PASSWORD}")" "${MYSQL_SOCKET}"
} > "${MYSQL_CLIENT_DEFAULTS}"
chmod 0600 "${MYSQL_CLIENT_DEFAULTS}"

if [[ -s "${MYSQL_MANIFEST}" ]]; then
    printf '%s\n' 'Running trusted initialization imports in lexical order'
    exec {manifest_fd}<"${MYSQL_MANIFEST}"
    while IFS= read -r -u "${manifest_fd}" import_file; do
        case "${import_file}" in
            *.sql|*.sql.gz) [[ -f "${import_file}" && -r "${import_file}" ]] ;;
            *) [[ -f "${import_file}" && -r "${import_file}" && -x "${import_file}" ]] ;;
        esac || { printf '%s\n' 'validated initialization import became unavailable' >&2; exit 1; }
        case "${import_file}" in
            *.sql)
                mysql_bootstrap < "${import_file}" &
                IMPORT_CLIENT_PID=$!
                wait "${IMPORT_CLIENT_PID}"
                IMPORT_CLIENT_PID=''
                ;;
            *.sql.gz)
                IMPORT_FIFO="/run/mysql/import-stream.$$"
                mkfifo -m 0600 "${IMPORT_FIFO}"
                gzip -cd -- "${import_file}" > "${IMPORT_FIFO}" &
                IMPORT_DECOMPRESS_PID=$!
                mysql_bootstrap < "${IMPORT_FIFO}" &
                IMPORT_CLIENT_PID=$!
                wait "${IMPORT_CLIENT_PID}"
                IMPORT_CLIENT_PID=''
                wait "${IMPORT_DECOMPRESS_PID}"
                IMPORT_DECOMPRESS_PID=''
                rm -f "${IMPORT_FIFO}"
                IMPORT_FIFO=''
                ;;
            *)
                if [[ -x "${import_file}" && -f "${import_file}" ]]; then
                    MYSQL_INIT_DEFAULTS_FILE="${MYSQL_CLIENT_DEFAULTS}" "${import_file}" </dev/null &
                    IMPORT_CLIENT_PID=$!
                    wait "${IMPORT_CLIENT_PID}"
                    IMPORT_CLIENT_PID=''
                fi
                ;;
        esac
    done
    exec {manifest_fd}<&-
fi

timeout --kill-after=1s 10s mysqladmin --defaults-extra-file="${MYSQL_CLIENT_DEFAULTS}" shutdown
wait "${MYSQLD_PID}"
MYSQLD_PID=''
mysql_write_state ready
printf '%s\n' 'MySQL initialization completed.'
