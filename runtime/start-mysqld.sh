#!/usr/bin/env bash
set -euo pipefail

readonly MYSQL_STOP_GRACE_SECONDS="${MYSQL_STOP_GRACE_SECONDS:-20}"
readonly MYSQL_STOP_FAILURE_MARKER=/run/lamp/mysql-stop-failed

rm -f "${MYSQL_STOP_FAILURE_MARKER}"
mysqld --defaults-file=/run/mysql/docker-lamp.cnf --console &
mysqld_pid=$!

stop_mysqld() {
    local deadline

    trap - TERM INT
    kill -TERM "${mysqld_pid}" 2>/dev/null || true
    deadline=$((SECONDS + MYSQL_STOP_GRACE_SECONDS))
    while kill -0 "${mysqld_pid}" 2>/dev/null && (( SECONDS < deadline )); do
        sleep 1
    done
    if kill -0 "${mysqld_pid}" 2>/dev/null; then
        printf 'MySQL did not stop gracefully within %s seconds; forcing SIGKILL.\n' \
            "${MYSQL_STOP_GRACE_SECONDS}" >&2
        printf 'forced MySQL shutdown\n' > "${MYSQL_STOP_FAILURE_MARKER}"
        kill -KILL "${mysqld_pid}" 2>/dev/null || true
        wait "${mysqld_pid}" 2>/dev/null || true
        exit 1
    fi
    wait "${mysqld_pid}"
    exit $?
}

trap stop_mysqld TERM INT
wait "${mysqld_pid}"
