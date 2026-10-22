#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

trap 'test_failed "$LINENO"' ERR

restricted_run() {
    local container=$1
    shift
    docker run --detach --name "${container}" --read-only --user 1000:1000 \
        --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /run/lamp:uid=1000,gid=1000,mode=0755 \
        --tmpfs /run/mysql:uid=1000,gid=1000,mode=0755 \
        --tmpfs /tmp:uid=1000,gid=1000,mode=1777 \
        "$@" "docker-lamp-test:${SERVICE#web}" >/dev/null
}

wait_for_direct_service() {
    local container=$1 attempt apache_status mysql_status
    for ((attempt = 1; attempt <= 60; attempt++)); do
        if apache_status=$(docker exec "${container}" supervisorctl status apache2 2>/dev/null) \
            && mysql_status=$(docker exec "${container}" supervisorctl status mysqld 2>/dev/null) \
            && [[ "${apache_status}" == *" RUNNING "* && "${mysql_status}" == *" RUNNING "* ]]; then
            return 0
        fi
        sleep 1
    done
    docker logs "${container}" >&2 || true
    fail "${container} did not start"
}

assert_container_failed() {
    local container=$1 attempt
    for ((attempt = 1; attempt <= 35; attempt++)); do
        if [[ "$(docker inspect --format '{{.State.Running}}' "${container}")" == false ]]; then
            [[ "$(docker inspect --format '{{.State.ExitCode}}' "${container}")" != 0 ]] \
                || { docker logs "${container}" >&2 || true; fail "${container} exited successfully after a critical failure"; }
            return 0
        fi
        sleep 1
    done
    docker logs "${container}" >&2 || true
    fail "${container} stayed running after a critical failure"
}

run_failure_fixture() {
    local failure=$1
    local container="docker-lamp-${SERVICE}-${failure}"

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        -e "MYSQL_ADMIN_PASS=test-admin-password-${OS_VERSION}"
    wait_for_direct_service "${container}"
    case "${failure}" in
        apache2)
            docker exec "${container}" bash -ec 'kill -TERM "$(cat /run/lamp/apache2/apache2.pid)"'
            ;;
        mysqld)
            docker exec "${container}" bash -ec 'kill -TERM "$(cat /run/mysql/mysqld.pid)"'
            ;;
        watchdog)
            docker exec "${container}" bash -ec 'kill -TERM "$(cat /run/lamp/runtime-watchdog.pid)"'
            ;;
        control-channel)
            docker exec "${container}" bash -ec 'rm /run/lamp/supervisor/supervisor.sock; kill -TERM "$(cat /run/lamp/apache2/apache2.pid)"'
            ;;
        *) fail "unknown failure fixture ${failure}" ;;
    esac
    assert_container_failed "${container}"
    docker rm --force "${container}" >/dev/null
}

run_restricted_source_fixture() {
    local container="docker-lamp-source-${SERVICE}"
    local fixture_root state_root

    fixture_root=$(mktemp -d)
    state_root=$(mktemp -d)
    mkdir -p "${fixture_root}/public"
    printf 'selected-root\n' > "${fixture_root}/public/index.html"
    printf 'not-public\n' > "${fixture_root}/private.txt"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" \
        "docker-lamp-test:${SERVICE#web}" -R 1000:1000 /state >/dev/null

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" \
        --mount "type=bind,src=${fixture_root},dst=/app,readonly" \
        --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e APACHE_ROOT=/app/public \
        -e "MYSQL_ADMIN_PASS=test-admin-password-${OS_VERSION}"
    wait_for_direct_service "${container}"
    docker exec "${container}" bash -ec '
        test "$(id -u)" = 1000
        test "$(id -g)" = 1000
        test "$(ps -o uid= -p 1 | tr -d " ")" = 1000
        ! ps -eo uid= | tr -d " " | grep -Fxq 0
        test "$(awk "/CapEff/ {print \$2}" /proc/1/status)" = 0000000000000000
        test ! -w /app
        test -w /run/lamp
        test -w /run/mysql
        test -w /tmp
        test -w /var/lib/mysql
        test -z "$(find / -xdev -type f -perm /6000 -print 2>/dev/null)"
    '
    [[ "$(docker inspect --format '{{json .HostConfig.CapDrop}}' "${container}")" == *ALL* ]] \
        || fail "${container} did not drop all capabilities"
    [[ "$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "${container}")" == *no-new-privileges* ]] \
        || fail "${container} did not enable no-new-privileges"
    docker exec "${container}" curl --fail --silent http://127.0.0.1:8080/ | grep -Fxq selected-root
    ! docker exec "${container}" curl --fail --silent http://127.0.0.1:8080/private.txt >/dev/null 2>&1 \
        || fail "${container} exposed a file outside APACHE_ROOT"
    docker rm --force "${container}" >/dev/null
    rm -rf "${fixture_root}" "${state_root}"
}

run_denied_mount_fixture() {
    local container="docker-lamp-denied-${SERVICE}"

    docker rm --force "${container}" >/dev/null 2>&1 || true
    if docker run --rm --read-only --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /run/lamp:uid=1000,gid=1000,mode=0755 \
        --tmpfs /run/mysql:uid=1000,gid=1000,mode=0755 \
        --tmpfs /tmp:uid=1000,gid=1000,mode=1777 \
        --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0555 \
        -e "MYSQL_ADMIN_PASS=test-admin-password-${OS_VERSION}" \
        "docker-lamp-test:${SERVICE#web}" >/dev/null 2>&1; then
        fail "${SERVICE} accepted an unprepared MySQL data mount"
    fi
}

run_persistent_shutdown_fixture() {
    local volume="docker-lamp-rootless-${SERVICE}-${RANDOM}"
    local first="docker-lamp-persist-first-${SERVICE}"
    local second="docker-lamp-persist-second-${SERVICE}"
    local password="persist-password-${SERVICE}"
    local logs

    docker rm --force "${first}" "${second}" >/dev/null 2>&1 || true
    docker volume create "${volume}" >/dev/null
    restricted_run "${first}" --mount "type=volume,src=${volume},dst=/var/lib/mysql" -e "MYSQL_ADMIN_PASS=${password}"
    wait_for_direct_service "${first}"
    docker exec "${first}" env MYSQL_PWD="${password}" mysql --protocol=TCP -h 127.0.0.1 -uadmin \
        --execute 'CREATE DATABASE rootless_persistence_check'
    docker stop --time 70 "${first}" >/dev/null
    [[ "$(docker inspect --format '{{.State.ExitCode}}' "${first}")" == 0 ]] \
        || { docker logs "${first}" >&2 || true; fail "${first} did not stop cleanly on TERM"; }
    logs=$(docker logs "${first}" 2>&1)
    logs=${logs##*'port: 3306'}
    [[ "${logs}" == *'Shutdown complete'* ]] || fail "${first} did not log a clean final MySQL shutdown"
    docker rm "${first}" >/dev/null
    restricted_run "${second}" --mount "type=volume,src=${volume},dst=/var/lib/mysql" -e "MYSQL_ADMIN_PASS=${password}"
    wait_for_direct_service "${second}"
    docker exec "${second}" env MYSQL_PWD="${password}" mysql --protocol=TCP -h 127.0.0.1 -uadmin \
        --skip-column-names --batch --execute "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'rootless_persistence_check'" \
        | grep -Fxq rootless_persistence_check
    docker rm --force "${second}" >/dev/null
    docker volume rm "${volume}" >/dev/null
}

run_forced_shutdown_fixture() {
    local container="docker-lamp-forced-stop-${SERVICE}"
    local logs

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        -e "MYSQL_ADMIN_PASS=forced-stop-password-${SERVICE}"
    wait_for_direct_service "${container}"
    docker exec "${container}" bash -ec 'kill -STOP "$(cat /run/lamp/supervisor/supervisord.pid)"'
    docker stop --time 70 "${container}" >/dev/null
    [[ "$(docker inspect --format '{{.State.ExitCode}}' "${container}")" != 0 ]] \
        || { docker logs "${container}" >&2 || true; fail "${container} reported a clean exit after forced shutdown"; }
    logs=$(docker logs "${container}" 2>&1)
    [[ "${logs}" == *'cleanup timed out'* ]] || fail "${container} did not report forced cleanup timeout"
    docker rm "${container}" >/dev/null
}

run_mysql_force_kill_fixture() {
    local container="docker-lamp-mysql-force-kill-${SERVICE}"
    local logs

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        -e "MYSQL_ADMIN_PASS=mysql-force-kill-password-${SERVICE}"
    wait_for_direct_service "${container}"
    docker exec "${container}" bash -ec 'kill -STOP "$(cat /run/mysql/mysqld.pid)"'
    docker stop --time 40 "${container}" >/dev/null
    [[ "$(docker inspect --format '{{.State.ExitCode}}' "${container}")" != 0 ]] \
        || { docker logs "${container}" >&2 || true; fail "${container} reported a clean exit after forced MySQL shutdown"; }
    logs=$(docker logs "${container}" 2>&1)
    logs=${logs##*'port: 3306'}
    [[ "${logs}" == *'forcing SIGKILL'* ]] || fail "${container} did not force-kill the final MySQL daemon"
    [[ "${logs}" != *'Shutdown complete'* ]] || fail "${container} reported a clean final MySQL shutdown after SIGSTOP"
    docker rm "${container}" >/dev/null
}

run_mysql_lifecycle_fixture() {
    local state_root container interrupted secret='phase2-secret-must-not-appear'

    state_root=$(mktemp -d)
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" \
        "docker-lamp-test:${SERVICE#web}" -R 1000:1000 /state >/dev/null
    container="docker-lamp-invalid-input-${SERVICE}"
    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e "MYSQL_ADMIN_PASS=${secret}" -e MYSQL_ADMIN_PASS_FILE=/missing
    assert_container_failed "${container}"
    [[ -z "$(ls -A "${state_root}")" ]] || fail "${container} mutated a fresh volume before rejecting credentials"
    ! docker logs "${container}" 2>&1 | grep -Fq "${secret}" \
        || fail "${container} exposed a credential in diagnostics"
    docker rm "${container}" >/dev/null

    container="docker-lamp-interrupted-init-${SERVICE}"
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_ADMIN_PASS=phase2-interrupt-password
    for _ in $(seq 1 30); do
        [[ -f "${state_root}/.docker-lamp-mysql-state" ]] && break
        sleep 1
    done
    [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
        || { docker logs "${container}" >&2 || true; fail "${container} did not record initializing state"; }
    docker kill "${container}" >/dev/null
    docker rm "${container}" >/dev/null
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_ADMIN_PASS=phase2-interrupt-password
    assert_container_failed "${container}"
    ! docker logs "${container}" 2>&1 | grep -Fq 'Starting socket-only MySQL' \
        || fail "${container} replayed interrupted initialization"
    docker rm "${container}" >/dev/null
    rm -rf "${state_root}"
}

run_mysql_bind_fixture() {
    local container="docker-lamp-bind-${SERVICE}" peer_result

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        --network ci_default --network-alias "${container}" \
        -e MYSQL_BIND_ADDRESS=0.0.0.0 -e MYSQL_ADMIN_PASS=phase2-bind-password \
        -e MYSQL_USER_NAME=app -e MYSQL_USER_DB=appdb -e MYSQL_USER_PASS=phase2-app-password
    wait_for_direct_service "${container}"
    docker exec "${container}" env MYSQL_PWD=phase2-bind-password mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --skip-column-names --batch --execute "SELECT Host FROM mysql.user WHERE User = 'app'" | grep -Fxq '%'
    peer_result=$(docker run --rm --network ci_default --entrypoint mysql \
        -e MYSQL_PWD=phase2-app-password "docker-lamp-test:${SERVICE#web}" \
        --protocol=TCP -h "${container}" -P 3306 -uapp --connect-timeout=5 --skip-column-names --batch --execute 'SELECT 1')
    [[ "${peer_result}" == 1 ]] || fail "${container} did not allow explicit non-loopback peer access"
    docker exec "${container}" bash -ec '
        grep -Fx "bind-address = 0.0.0.0" /run/mysql/docker-lamp.cnf
        grep -Fx "port = 3306" /run/mysql/docker-lamp.cnf
        grep -Fx "mysqlx = 0" /run/mysql/docker-lamp.cnf
    '
    docker rm --force "${container}" >/dev/null
}

build_php_artifacts
start_fresh_stack

for variant in "${VARIANTS[@]}"; do
    select_variant "${variant}"
    echo "Checking rootless runtime remediation for Ubuntu ${OS_VERSION} (${SERVICE})"

    wait_for "${SERVICE} Supervisor apache2" supervisor_running apache2
    wait_for "${SERVICE} Supervisor mysqld" supervisor_running mysqld
    wait_for "${SERVICE} Apache HTTP" http_page_available
    web_exec bash -ec '
        test "$(id -u)" = 1000
        test "$(id -g)" = 1000
        test "$(ps -o uid= -p 1 | tr -d " ")" = 1000
        test "$(ps -o uid= -C apache2 | tr -d " " | sort -u)" = 1000
        test "$(ps -o uid= -C mysqld | tr -d " " | sort -u)" = 1000
        ! ps -eo uid= | tr -d " " | grep -Fxq 0
        test ! -w /app
        test "$(stat -c "%u:%g" /app)" = 0:0
        ! chmod u+w /app
        ! chmod u+w /app/index.php
        ! touch /app/runtime-write-test
    '
    for retired in RUNTIME_UID RUNTIME_GID RUNTIME_PRIVILEGED_COMPAT RUNTIME_ALLOW_ROOT; do
        if web_exec env "${retired}=1" /run.sh >/dev/null 2>&1; then
            fail "${SERVICE} accepted retired control ${retired}"
        fi
    done

    run_restricted_source_fixture
    run_denied_mount_fixture
    run_mysql_lifecycle_fixture
    run_mysql_bind_fixture
    run_persistent_shutdown_fixture
    run_failure_fixture apache2
    run_failure_fixture mysqld
    run_failure_fixture watchdog
    run_failure_fixture control-channel
    [[ "${variant}" == 2204 ]] && run_forced_shutdown_fixture
    [[ "${variant}" == 2204 ]] && run_mysql_force_kill_fixture
done

echo "All rootless runtime remediation checks passed."
