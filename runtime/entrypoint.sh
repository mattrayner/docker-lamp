#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source /usr/local/lib/docker-lamp/runtime.sh

validate_rootless_runtime
validate_apache_root
mysql_validate_bind_address

ensure_runtime_directory /run/lamp
ensure_runtime_directory /run/lamp/apache2
ensure_runtime_directory /run/lamp/php/conf.d
ensure_runtime_directory /run/lamp/supervisor
ensure_runtime_directory /run/mysql
ensure_runtime_directory /tmp

cat > /run/lamp/php/conf.d/99-docker-lamp.ini <<EOF
; Generated at container start in a declared writable runtime directory.
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}
post_max_size = ${PHP_POST_MAX_SIZE}
date.timezone = ${PHP_TIMEZONE}
mysqli.default_socket = /run/mysql/mysqld.sock
pdo_mysql.default_socket = /run/mysql/mysqld.sock
EOF

cat > /run/mysql/docker-lamp.cnf <<'EOF'
[mysqld]
bind-address = __MYSQL_BIND_ADDRESS__
port = 3306
mysqlx = 0
datadir = /var/lib/mysql
socket = /run/mysql/mysqld.sock
pid-file = /run/mysql/mysqld.pid
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci
EOF

sed -i "s/__MYSQL_BIND_ADDRESS__/${MYSQL_BIND_ADDRESS}/" /run/mysql/docker-lamp.cnf

mysql_state=$(mysql_data_state)
case "${mysql_state}" in
    fresh)
        # Validate and materialize credentials before the first datadir write.
        mysql_preflight_first_run
        mysql_write_state initializing
        /usr/local/bin/mysql-init
        ;;
    ready)
        printf '%s\n' 'MySQL lifecycle state is ready; skipping account setup and initialization imports.'
        ;;
    legacy)
        printf '%s\n' 'WARNING: legacy MySQL volume has no lifecycle state; starting without account mutation or initialization imports. Back up before migration.' >&2
        ;;
    initializing|inconsistent)
        runtime_error "MySQL data directory is ${mysql_state}; refusing to start an interrupted or inconsistent volume"
        ;;
esac

/usr/bin/supervisord -c /etc/supervisor/supervisord.conf &
supervisord_pid=$!
/usr/local/bin/supervisor-watchdog &
watchdog_pid=$!
printf '%s\n' "${watchdog_pid}" > /run/lamp/runtime-watchdog.pid

cleanup_in_progress=0

cleanup() {
    local requested_status=$1
    local reason=$2
    local deadline timed_out=0 final_status=${requested_status}

    (( cleanup_in_progress == 0 )) || exit 1
    cleanup_in_progress=1
    trap - TERM INT
    printf 'docker-lamp runtime cleanup: %s\n' "${reason}" >&2
    kill -TERM "${watchdog_pid}" 2>/dev/null || true
    kill -TERM "${supervisord_pid}" 2>/dev/null || true
    # Supervisor stops apache2 (15 seconds) then mysqld (30 seconds). Keep a
    # margin above that ordered 45-second budget while retaining a hard bound.
    deadline=$((SECONDS + 60))
    while { kill -0 "${supervisord_pid}" 2>/dev/null || kill -0 "${watchdog_pid}" 2>/dev/null; } \
        && (( SECONDS < deadline )); do
        sleep 1
    done
    if kill -0 "${supervisord_pid}" 2>/dev/null || kill -0 "${watchdog_pid}" 2>/dev/null; then
        timed_out=1
        printf 'docker-lamp runtime cleanup timed out; forcing process termination.\n' >&2
        kill -KILL "${watchdog_pid}" 2>/dev/null || true
        kill -KILL "${supervisord_pid}" 2>/dev/null || true
    fi
    wait "${watchdog_pid}" 2>/dev/null || true
    wait "${supervisord_pid}" 2>/dev/null || true
    (( timed_out == 0 )) || exit 1
    [[ ! -e /run/lamp/mysql-stop-failed ]] || final_status=1
    exit "${final_status}"
}

trap 'cleanup 0 "received termination signal"' TERM INT
set +e
wait -n "${supervisord_pid}" "${watchdog_pid}"
status=$?
set -e
cleanup 1 "critical runtime process exited with status ${status}"
