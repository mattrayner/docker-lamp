#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

trap 'test_failed "$LINENO"' ERR

runtime_test_image() {
    if [[ "${PREBUILT_FINAL_IMAGES:-0}" == 1 ]]; then
        printf '%s' "${TEST_IMAGE}"
    else
        printf 'docker-lamp-test:%s' "${SERVICE#web}"
    fi
}

restricted_run() {
    local container=$1
    shift
    docker run --detach --name "${container}" --read-only --user 1000:1000 \
        --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /run/lamp:uid=1000,gid=1000,mode=0755 \
        --tmpfs /run/mysql:uid=1000,gid=1000,mode=0755 \
        --tmpfs /tmp:uid=1000,gid=1000,mode=1777 \
        "$@" -e MYSQL_USE_NATIVE_AIO=0 "$(runtime_test_image)" >/dev/null
}

default_native_aio_run() {
    local container=$1
    shift
    docker run --detach --name "${container}" --read-only --user 1000:1000 \
        --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /run/lamp:uid=1000,gid=1000,mode=0755 \
        --tmpfs /run/mysql:uid=1000,gid=1000,mode=0755 \
        --tmpfs /tmp:uid=1000,gid=1000,mode=1777 \
        "$@" "$(runtime_test_image)" >/dev/null
}

rootless_resource_name() {
    printf 'docker-lamp-%s-%s' "${COMPOSE_PROJECT}" "$1"
}

# Fixtures pre-provision host storage for the fixed runtime UID, and MySQL
# writes UID 1000-owned files into it. When the host user differs (as on CI
# runners), sticky /tmp blocks removal, so return ownership before deleting.
remove_fixture_paths() {
    local entry index=0
    local -a mounts=() targets=()
    for entry in "$@"; do
        [[ -e "${entry}" ]] || continue
        mounts+=(--mount "type=bind,src=${entry},dst=/cleanup/${index}")
        targets+=("/cleanup/${index}")
        index=$((index + 1))
    done
    if ((${#targets[@]} > 0)); then
        docker run --rm --user 0:0 --entrypoint /bin/chown "${mounts[@]}" \
            "$(runtime_test_image)" -R "$(id -u):$(id -g)" "${targets[@]}" >/dev/null
    fi
    rm -rf -- "$@"
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

apache_listener_present() {
    local container=$1 port=$2

    docker exec "${container}" bash -ec '
        port=$1
        pattern="^[[:space:]]*[0-9]+: [0-9A-Fa-f]+:${port} [0-9A-Fa-f]+:0000 0A "
        grep -Eq "${pattern}" /proc/net/tcp /proc/net/tcp6
    ' _ "${port}"
}

run_failure_fixture() {
    local failure=$1
    local container
    container=$(rootless_resource_name "${SERVICE}-${failure}")

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
    local container
    container=$(rootless_resource_name "source-${SERVICE}")
    local fixture_root state_root

    fixture_root=$(mktemp -d)
    state_root=$(mktemp -d)
    mkdir -p "${fixture_root}/public"
    printf 'selected-root\n' > "${fixture_root}/public/index.html"
    printf 'not-public\n' > "${fixture_root}/private.txt"
    # CI's checkout user is not the fixed runtime UID. Make this host-owned,
    # read-only source fixture traversable before mounting it at /app.
    chmod 0755 "${fixture_root}" "${fixture_root}/public"
    chmod 0644 "${fixture_root}/public/index.html" "${fixture_root}/private.txt"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" \
        "$(runtime_test_image)" -R 1000:1000 /state >/dev/null

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
    remove_fixture_paths "${fixture_root}" "${state_root}"
}

run_supervisor_restart_fixture() {
    local container
    container=$(rootless_resource_name "supervisor-restart-${SERVICE}")

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        -e "MYSQL_ADMIN_PASS=test-admin-password-${OS_VERSION}"
    wait_for_direct_service "${container}"
    docker exec "${container}" supervisorctl restart apache2 >/dev/null
    wait_for_direct_service "${container}"
    docker exec "${container}" curl --fail --silent http://127.0.0.1:8080/ | grep -q 'Welcome to'
    docker rm --force "${container}" >/dev/null
}

run_denied_mount_fixture() {
    local container
    container=$(rootless_resource_name "denied-${SERVICE}")

    docker rm --force "${container}" >/dev/null 2>&1 || true
    if docker run --rm --read-only --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges \
        --tmpfs /run/lamp:uid=1000,gid=1000,mode=0755 \
        --tmpfs /run/mysql:uid=1000,gid=1000,mode=0755 \
        --tmpfs /tmp:uid=1000,gid=1000,mode=1777 \
        --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0555 \
        -e "MYSQL_ADMIN_PASS=test-admin-password-${OS_VERSION}" \
        "$(runtime_test_image)" >/dev/null 2>&1; then
        fail "${SERVICE} accepted an unprepared MySQL data mount"
    fi
}

run_mysql_native_aio_configuration_fixture() {
    local container
    container=$(rootless_resource_name "native-aio-default-${SERVICE}")

    docker rm --force "${container}" >/dev/null 2>&1 || true
    default_native_aio_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        -e "MYSQL_ADMIN_PASS=native-aio-default-password-${SERVICE}"
    wait_for_direct_service "${container}"
    docker exec "${container}" grep -Fx 'innodb-use-native-aio = 1' /run/mysql/docker-lamp.cnf
    docker rm --force "${container}" >/dev/null
}

run_disabled_php_overrides_fixture() {
    local container override_root
    container=$(rootless_resource_name "overrides-disabled-${SERVICE}")
    override_root=$(mktemp -d)
    chmod 000 "${override_root}"

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        --mount "type=bind,src=${override_root},dst=/etc/docker-lamp/php/conf.d,readonly" \
        -e "MYSQL_ADMIN_PASS=overrides-disabled-password-${SERVICE}" -e PHP_USER_OVERRIDES_DISABLED=1
    wait_for_direct_service "${container}"
    docker exec "${container}" env PHP_USER_OVERRIDES_DISABLED=1 php -r \
        'exit(extension_loaded("xdebug") ? 1 : 0);'
    docker rm --force "${container}" >/dev/null
    chmod 700 "${override_root}"
    rmdir "${override_root}"
}

run_persistent_shutdown_fixture() {
    local volume first second
    volume=$(rootless_resource_name "rootless-${SERVICE}-${RANDOM}")
    first=$(rootless_resource_name "persist-first-${SERVICE}")
    second=$(rootless_resource_name "persist-second-${SERVICE}")
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
    local container
    container=$(rootless_resource_name "forced-stop-${SERVICE}")
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
    local container
    container=$(rootless_resource_name "mysql-force-kill-${SERVICE}")
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
        "$(runtime_test_image)" -R 1000:1000 /state >/dev/null
    container=$(rootless_resource_name "invalid-input-${SERVICE}")
    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e "MYSQL_ADMIN_PASS=${secret}" -e MYSQL_ADMIN_PASS_FILE=/missing
    assert_container_failed "${container}"
    [[ -z "$(ls -A "${state_root}")" ]] || fail "${container} mutated a fresh volume before rejecting credentials"
    ! docker logs "${container}" 2>&1 | grep -Fq "${secret}" \
        || fail "${container} exposed a credential in diagnostics"
    docker rm "${container}" >/dev/null

    container=$(rootless_resource_name "invalid-bind-${SERVICE}")
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_BIND_ADDRESS='::ffff:127.0.0.1' -e MYSQL_ADMIN_PASS=ignored
    assert_container_failed "${container}"
    [[ -z "$(ls -A "${state_root}")" ]] || fail "${container} mutated a fresh volume for a rejected mapped IPv6 address"
    docker rm "${container}" >/dev/null

    container=$(rootless_resource_name "invalid-identifier-${SERVICE}")
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_ADMIN_PASS=ignored -e MYSQL_USER_NAME='bad user' -e MYSQL_USER_DB=valid -e MYSQL_USER_PASS=ignored
    assert_container_failed "${container}"
    [[ -z "$(ls -A "${state_root}")" ]] || fail "${container} mutated a fresh volume for a rejected identifier"
    docker rm "${container}" >/dev/null

    container=$(rootless_resource_name "invalid-database-${SERVICE}")
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_ADMIN_PASS=ignored -e MYSQL_USER_NAME=valid -e MYSQL_USER_DB='a.b' -e MYSQL_USER_PASS=ignored
    assert_container_failed "${container}"
    [[ -z "$(ls -A "${state_root}")" ]] || fail "${container} mutated a fresh volume for a rejected database identifier"
    docker rm "${container}" >/dev/null

    container=$(rootless_resource_name "interrupted-init-${SERVICE}")
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
    remove_fixture_paths "${state_root}"
}

run_mysql_bind_fixture() {
    local container peer_result
    container=$(rootless_resource_name "bind-${SERVICE}")

    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        --network "${COMPOSE_NETWORK}" --network-alias "${container}" \
        -e MYSQL_BIND_ADDRESS=0.0.0.0 -e MYSQL_ADMIN_PASS=phase2-bind-password \
        -e MYSQL_USER_NAME=app -e MYSQL_USER_DB=appdb -e MYSQL_USER_PASS=phase2-app-password
    wait_for_direct_service "${container}"
    docker exec "${container}" env MYSQL_PWD=phase2-bind-password mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --skip-column-names --batch --execute "SELECT Host FROM mysql.user WHERE User = 'app'" | grep -Fxq '%'
    peer_result=$(docker run --rm --network "${COMPOSE_NETWORK}" --entrypoint mysql \
        -e MYSQL_PWD=phase2-app-password "$(runtime_test_image)" \
        --protocol=TCP -h "${container}" -P 3306 -uapp --connect-timeout=5 --skip-column-names --batch --execute 'SELECT 1')
    [[ "${peer_result}" == 1 ]] || fail "${container} did not allow explicit non-loopback peer access"
    docker exec "${container}" bash -ec '
        grep -Fx "bind-address = 0.0.0.0" /run/mysql/docker-lamp.cnf
        grep -Fx "port = 3306" /run/mysql/docker-lamp.cnf
        grep -Fx "mysqlx = 0" /run/mysql/docker-lamp.cnf
        ! grep -Eq ":8124[[:space:]]" /proc/net/tcp /proc/net/tcp6
    '
    docker rm --force "${container}" >/dev/null
}

run_mysql_credential_fixture() {
    local state_root secret_root container logs
    local admin_password='admin space\\quote"single' app_password='app space\\quote"single'

    state_root=$(mktemp -d)
    secret_root=$(mktemp -d)
    printf '%s' "${admin_password}" > "${secret_root}/admin"
    printf '%s' "${app_password}" > "${secret_root}/app"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${secret_root},dst=/secrets" \
        "$(runtime_test_image)" -R 1000:1000 /state /secrets >/dev/null
    container=$(rootless_resource_name "credentials-${SERVICE}")
    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${secret_root},dst=/secrets,readonly" \
        -e MYSQL_ADMIN_PASS_FILE=/secrets/admin -e MYSQL_USER_NAME=app -e MYSQL_USER_DB='app%_db' \
        -e MYSQL_USER_PASS_FILE=/secrets/app
    wait_for_direct_service "${container}"
    logs=$(docker logs "${container}" 2>&1)
    [[ "${logs}" != *"${admin_password}"* && "${logs}" != *"${app_password}"* ]] \
        || fail "${container} exposed a credential in raw logs"
    docker exec "${container}" env MYSQL_PWD="${admin_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock \
        -uadmin --execute 'SELECT 1' >/dev/null
    ! docker exec "${container}" env MYSQL_PWD="${admin_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock \
        -uroot --execute 'SELECT 1' >/dev/null 2>&1 || fail "${container} accepted locked bootstrap root"
    docker exec "${container}" env MYSQL_PWD="${admin_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock \
        -uadmin --execute 'CREATE DATABASE `appXXdb`' >/dev/null
    ! docker exec "${container}" env MYSQL_PWD="${app_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock \
        -uapp --execute 'USE `appXXdb`' >/dev/null 2>&1 || fail "${container} wildcard grant matched a similarly named database"
    docker exec "${container}" env MYSQL_PWD="${app_password}" php -r '
        $db = mysqli_connect("localhost", "app", getenv("MYSQL_PWD"), "app%_db", 3306, "/run/mysql/mysqld.sock");
        exit($db && mysqli_query($db, "SELECT 1") ? 0 : 1);
    '
    docker rm --force "${container}" >/dev/null
    remove_fixture_paths "${state_root}" "${secret_root}"
}

run_import_manifest_fixture() {
    local state_root imports_root container result

    state_root=$(mktemp -d)
    imports_root=$(mktemp -d)
    printf '%s\n' 'CREATE DATABASE import_order; CREATE TABLE import_order.steps (step INT); INSERT INTO import_order.steps VALUES (1);' > "${imports_root}/10-first.sql"
    printf '%s\n' '#!/usr/bin/env bash' 'read -r ignored || true' 'mysql --defaults-extra-file="$MYSQL_INIT_DEFAULTS_FILE" --execute "INSERT INTO import_order.steps VALUES (2)"' > "${imports_root}/20-stdin-hook"
    chmod 0755 "${imports_root}/20-stdin-hook"
    printf '%s\n' 'INSERT INTO import_order.steps VALUES (3);' | gzip -c > "${imports_root}/30-last.sql.gz"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
        "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null
    container=$(rootless_resource_name "import-manifest-${SERVICE}")
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" -e MYSQL_ADMIN_PASS=import-password
    wait_for_direct_service "${container}"
    result=$(docker exec "${container}" env MYSQL_PWD=import-password mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --skip-column-names --batch --execute 'SELECT GROUP_CONCAT(step ORDER BY step) FROM import_order.steps')
    [[ "${result}" == 1,2,3 ]] || fail "${container} did not execute imports in lexical order"
    docker rm --force "${container}" >/dev/null
    remove_fixture_paths "${state_root}" "${imports_root}"
}

run_import_failure_fixture() {
    local state_root imports_root container

    state_root=$(mktemp -d)
    imports_root=$(mktemp -d)
    printf '%s\n' 'CREATE DATABASE import_failure;' > "${imports_root}/10-schema.sql"
    printf '%s\n' '#!/usr/bin/env bash' 'rm -f /docker-entrypoint-initdb.d/30-removed.sql' > "${imports_root}/20-remove-next"
    chmod 0755 "${imports_root}/20-remove-next"
    printf '%s\n' 'CREATE TABLE import_failure.must_not_run (id INT);' > "${imports_root}/30-removed.sql"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
        "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null

    container=$(rootless_resource_name "import-failure-${SERVICE}")
    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d" -e MYSQL_ADMIN_PASS=import-failure-password
    assert_container_failed "${container}"
    docker logs "${container}" 2>&1 | grep -Fq 'validated initialization import became unavailable' \
        || fail "${container} did not reject an import removed after preflight"
    [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
        || fail "${container} did not preserve initializing state after import failure"
    docker rm "${container}" >/dev/null

    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        -e MYSQL_ADMIN_PASS=import-failure-password
    assert_container_failed "${container}"
    ! docker logs "${container}" 2>&1 | grep -Fq 'Starting socket-only MySQL' \
        || fail "${container} replayed imports after a failed initialization"
    docker rm "${container}" >/dev/null
    remove_fixture_paths "${state_root}" "${imports_root}"
}

run_ready_legacy_state_fixture() {
    local state_root imports_root first second third fourth container result
    local original_password='lifecycle-original-password' changed_password='lifecycle-changed-password'

    state_root=$(mktemp -d)
    imports_root=$(mktemp -d)
    printf '%s\n' 'CREATE DATABASE imports_must_not_replay;' > "${imports_root}/10-no-replay.sql"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
        "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null
    first=$(rootless_resource_name "ready-first-${SERVICE}")
    second=$(rootless_resource_name "ready-second-${SERVICE}")
    third=$(rootless_resource_name "legacy-${SERVICE}")
    fourth=$(rootless_resource_name "inconsistent-${SERVICE}")
    docker rm --force "${first}" "${second}" "${third}" "${fourth}" >/dev/null 2>&1 || true

    restricted_run "${first}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" -e "MYSQL_ADMIN_PASS=${original_password}"
    wait_for_direct_service "${first}"
    docker stop --time 70 "${first}" >/dev/null
    docker rm "${first}" >/dev/null

    restricted_run "${second}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" \
        -e "MYSQL_ADMIN_PASS=${changed_password}"
    wait_for_direct_service "${second}"
    docker exec "${second}" env MYSQL_PWD="${original_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --execute 'SELECT 1' >/dev/null
    ! docker exec "${second}" env MYSQL_PWD="${changed_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --execute 'SELECT 1' >/dev/null 2>&1 \
        || fail "${second} changed credentials on a ready volume"
    result=$(docker exec "${second}" env MYSQL_PWD="${original_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --skip-column-names --batch --execute "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'imports_must_not_replay'")
    [[ "${result}" == 0 ]] || fail "${second} replayed imports on a ready volume"
    docker stop --time 70 "${second}" >/dev/null
    docker rm "${second}" >/dev/null

    rm "${state_root}/.docker-lamp-mysql-state"
    restricted_run "${third}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" \
        -e "MYSQL_ADMIN_PASS=${changed_password}"
    wait_for_direct_service "${third}"
    docker exec "${third}" env MYSQL_PWD="${original_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --execute 'SELECT 1' >/dev/null
    ! docker exec "${third}" env MYSQL_PWD="${changed_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --execute 'SELECT 1' >/dev/null 2>&1 \
        || fail "${third} changed credentials on a legacy volume"
    result=$(docker exec "${third}" env MYSQL_PWD="${original_password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin --skip-column-names --batch --execute "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'imports_must_not_replay'")
    [[ "${result}" == 0 ]] || fail "${third} replayed imports on a legacy volume"
    docker stop --time 70 "${third}" >/dev/null
    docker rm "${third}" >/dev/null

    printf '%s\n' broken > "${state_root}/.docker-lamp-mysql-state"
    restricted_run "${fourth}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" -e "MYSQL_ADMIN_PASS=${original_password}"
    assert_container_failed "${fourth}"
    ! docker logs "${fourth}" 2>&1 | grep -Fq 'Starting socket-only MySQL' \
        || fail "${fourth} initialized an inconsistent volume"
    docker rm "${fourth}" >/dev/null
    remove_fixture_paths "${state_root}" "${imports_root}"
}

run_unresponsive_init_shutdown_fixture() {
    local state_root imports_root container started elapsed

    state_root=$(mktemp -d)
    imports_root=$(mktemp -d)
    printf '%s\n' '#!/usr/bin/env bash' 'kill -STOP "$(cat /run/mysql/mysqld-init.pid)"' > "${imports_root}/10-stop-temporary-server"
    chmod 0755 "${imports_root}/10-stop-temporary-server"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
        "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null
    container=$(rootless_resource_name "unresponsive-init-${SERVICE}")
    docker rm --force "${container}" >/dev/null 2>&1 || true
    started=${SECONDS}
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" -e MYSQL_ADMIN_PASS=unresponsive-init-password
    for _ in $(seq 1 55); do
        if [[ "$(docker inspect --format '{{.State.Running}}' "${container}")" == false ]]; then
            break
        fi
        sleep 1
    done
    elapsed=$((SECONDS - started))
    assert_container_failed "${container}"
    (( elapsed <= 50 )) || fail "${container} did not bound temporary-server shutdown (${elapsed}s)"
    docker logs "${container}" 2>&1 | grep -Fq 'forcing termination' \
        || fail "${container} did not force termination of the unresponsive temporary server"
    docker rm "${container}" >/dev/null
    remove_fixture_paths "${state_root}" "${imports_root}"
}

run_term_during_import_fixture() {
    local state_root imports_root container initializer_pid logs

    state_root=$(mktemp -d)
    imports_root=$(mktemp -d)
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "blocking validated import started"' 'while :; do sleep 1; done' > "${imports_root}/10-blocking-import"
    chmod 0755 "${imports_root}/10-blocking-import"
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
        "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null
    container=$(rootless_resource_name "term-import-${SERVICE}")
    docker rm --force "${container}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" -e MYSQL_ADMIN_PASS=term-import-password
    for _ in $(seq 1 30); do
        docker logs "${container}" 2>&1 | grep -Fq 'blocking validated import started' && break
        sleep 1
    done
    docker logs "${container}" 2>&1 | grep -Fq 'blocking validated import started' \
        || { docker logs "${container}" >&2 || true; fail "${container} did not reach the blocking import"; }
    [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
        || fail "${container} did not preserve initializing state during import"
    initializer_pid=$(docker exec "${container}" sh -ec "ps -eo pid=,args= | awk '/bash \\/usr\\/local\\/bin\\/mysql-init$/ { print \$1; exit }'")
    [[ -n "${initializer_pid}" ]] || fail "${container} did not expose the initializer process"
    docker exec "${container}" kill -TERM "${initializer_pid}"
    assert_container_failed "${container}"
    [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
        || fail "${container} changed lifecycle state after TERM during import"
    logs=$(docker logs "${container}" 2>&1)
    [[ "${logs}" != *'supervisord started'* && "${logs}" != *"spawned: 'apache2'"* ]] \
        || fail "${container} started Supervisor or HTTP while initialization was interrupted"
    docker rm "${container}" >/dev/null

    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" -e MYSQL_ADMIN_PASS=term-import-password
    assert_container_failed "${container}"
    ! docker logs "${container}" 2>&1 | grep -Fq 'Running trusted initialization imports' \
        || fail "${container} replayed imports after TERM during initialization"
    docker rm "${container}" >/dev/null
    remove_fixture_paths "${state_root}" "${imports_root}"
}

run_term_during_sql_import_fixture() {
    local format state_root imports_root container initializer_pid logs started elapsed

    for format in sql sql.gz; do
        state_root=$(mktemp -d)
        imports_root=$(mktemp -d)
        if [[ "${format}" == sql ]]; then
            printf '%s\n' 'DO SLEEP(60);' > "${imports_root}/10-blocking.sql"
        else
            printf '%s\n' 'DO SLEEP(60);' | gzip -c > "${imports_root}/10-blocking.sql.gz"
        fi
        docker run --rm --user 0:0 --entrypoint /bin/chown \
            --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${imports_root},dst=/imports" \
            "$(runtime_test_image)" -R 1000:1000 /state /imports >/dev/null
        container=$(rootless_resource_name "term-${format}-import-${SERVICE}")
        docker rm --force "${container}" >/dev/null 2>&1 || true
        restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
            --mount "type=bind,src=${imports_root},dst=/docker-entrypoint-initdb.d,readonly" -e MYSQL_ADMIN_PASS=term-sql-import-password
        for _ in $(seq 1 30); do
            docker logs "${container}" 2>&1 | grep -Fq 'Running trusted initialization imports in lexical order' && break
            sleep 1
        done
        docker logs "${container}" 2>&1 | grep -Fq 'Running trusted initialization imports in lexical order' \
            || { docker logs "${container}" >&2 || true; fail "${container} did not reach the blocking ${format} import"; }
        sleep 1
        [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
            || fail "${container} did not preserve initializing state during ${format} import"
        initializer_pid=$(docker exec "${container}" sh -ec "ps -eo pid=,args= | awk '/bash \\/usr\\/local\\/bin\\/mysql-init$/ { print \$1; exit }'")
        [[ -n "${initializer_pid}" ]] || fail "${container} did not expose the initializer process"
        started=${SECONDS}
        docker exec "${container}" kill -TERM "${initializer_pid}"
        assert_container_failed "${container}"
        elapsed=$((SECONDS - started))
        (( elapsed <= 20 )) || fail "${container} did not bound TERM cleanup for ${format} import (${elapsed}s)"
        [[ "$(<"${state_root}/.docker-lamp-mysql-state")" == initializing ]] \
            || fail "${container} changed lifecycle state after TERM during ${format} import"
        logs=$(docker logs "${container}" 2>&1)
        [[ "${logs}" != *'supervisord started'* && "${logs}" != *"spawned: 'apache2'"* ]] \
            || fail "${container} started Supervisor or HTTP while ${format} initialization was interrupted"
        docker rm "${container}" >/dev/null

        restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" -e MYSQL_ADMIN_PASS=term-sql-import-password
        assert_container_failed "${container}"
        ! docker logs "${container}" 2>&1 | grep -Fq 'Running trusted initialization imports' \
            || fail "${container} replayed ${format} imports after TERM during initialization"
        docker rm "${container}" >/dev/null
        remove_fixture_paths "${state_root}" "${imports_root}"
    done
}

run_phase3_transport_php_backup_fixture() {
    local container invalid http_binding https_binding http_port https_port
    container=$(rootless_resource_name "phase3-${SERVICE}")
    invalid=$(rootless_resource_name "phase3-invalid-tls-${SERVICE}")
    local state_root app_root override_root tls_root dump_file stderr_file password="phase3-password-${SERVICE}"

    state_root=$(mktemp -d)
    app_root=$(mktemp -d)
    override_root=$(mktemp -d)
    tls_root=$(mktemp -d)
    dump_file=$(mktemp)
    stderr_file=$(mktemp)
    printf '%s\n' '<?php echo extension_loaded("xdebug") ? "xdebug=on memory=" . ini_get("memory_limit") : "xdebug=off";' > "${app_root}/xdebug.php"
    printf '%s\n' 'memory_limit = 17M' > "${override_root}/99-phase3.ini"
    docker run --rm --user 0:0 --entrypoint openssl --mount "type=bind,src=${tls_root},dst=/tls" \
        "$(runtime_test_image)" req -x509 -newkey rsa:2048 -nodes -days 1 \
        -subj /CN=phase3.local -addext subjectAltName=DNS:phase3.local \
        -keyout /tls/key.pem -out /tls/cert.pem >/dev/null 2>&1
    docker run --rm --user 0:0 --entrypoint /bin/chown \
        --mount "type=bind,src=${state_root},dst=/state" --mount "type=bind,src=${tls_root},dst=/tls" \
        "$(runtime_test_image)" -R 1000:1000 /state /tls >/dev/null

    docker rm --force "${container}" "${invalid}" >/dev/null 2>&1 || true
    restricted_run "${container}" --mount "type=bind,src=${state_root},dst=/var/lib/mysql" \
        --mount "type=bind,src=${app_root},dst=/app,readonly" \
        --mount "type=bind,src=${override_root},dst=/etc/docker-lamp/php/conf.d,readonly" \
        --mount "type=bind,src=${tls_root},dst=/tls,readonly" \
        --publish 127.0.0.1::8080 --publish 127.0.0.1::8443 \
        -e "MYSQL_ADMIN_PASS=${password}" -e APACHE_TLS_ENABLED=1 \
        -e APACHE_TLS_CERT_FILE=/tls/cert.pem -e APACHE_TLS_KEY_FILE=/tls/key.pem -e XDEBUG_ENABLED=1
    wait_for_direct_service "${container}"
    http_binding=$(docker port "${container}" 8080/tcp)
    https_binding=$(docker port "${container}" 8443/tcp)
    case "${http_binding}" in 127.0.0.1:*) http_port=${http_binding##*:} ;; *) fail "${container} did not publish HTTP on loopback" ;; esac
    case "${https_binding}" in 127.0.0.1:*) https_port=${https_binding##*:} ;; *) fail "${container} did not publish HTTPS on loopback" ;; esac
    [[ "${http_port}" =~ ^[0-9]+$ && "${https_port}" =~ ^[0-9]+$ ]] \
        || fail "${container} published an invalid TLS fixture port"
    apache_listener_present "${container}" 1F90
    apache_listener_present "${container}" 20FB
    ! apache_listener_present "${container}" 01BB || fail "${container} listened on forbidden port 443"
    curl --silent --show-error --dump-header - --output /dev/null --noproxy '*' \
        --connect-to "phase3.local:80:127.0.0.1:${http_port}" http://phase3.local/ \
        | grep -Fxq $'Location: https://phase3.local/\r'
    curl --silent --show-error --dump-header - --output /dev/null --noproxy '*' \
        --connect-to "phase3.local:80:127.0.0.1:${http_port}" -H 'X-Forwarded-Proto: https' http://phase3.local/ \
        | grep -Fxq $'Location: https://phase3.local/\r'
    curl --fail --silent --cacert "${tls_root}/cert.pem" --location --noproxy '*' \
        --connect-to "phase3.local:80:127.0.0.1:${http_port}" --connect-to "phase3.local:443:127.0.0.1:${https_port}" \
        http://phase3.local/xdebug.php \
        | grep -Fxq 'xdebug=on memory=17M'
    docker exec "${container}" env PHP_USER_OVERRIDES_DISABLED=1 XDEBUG_ENABLED=0 php -r \
        'exit(extension_loaded("xdebug") || ini_get("memory_limit") === "17M" ? 1 : 0);'
    docker exec "${container}" env MYSQL_PWD="${password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --execute 'CREATE DATABASE phase3_backup; CREATE TABLE phase3_backup.sample (value_text VARCHAR(20)); INSERT INTO phase3_backup.sample VALUES ("preserved");'
    docker exec "${container}" env MYSQL_ADMIN_PASS="${password}" docker-lamp-backup --database phase3_backup \
        > "${dump_file}" 2> "${stderr_file}"
    grep -Fq 'INSERT INTO `sample`' "${dump_file}"
    ! grep -Eq '^(--|/\*|CREATE|INSERT|DROP|LOCK|UNLOCK)' "${stderr_file}" \
        || fail "${container} wrote backup SQL to stderr"
    if docker exec -i "${container}" env MYSQL_ADMIN_PASS="${password}" docker-lamp-restore --database missing_phase3 < /dev/null; then
        fail "${container} restored into a missing target database"
    fi
    if docker exec "${container}" docker-lamp-restore --database; then
        fail "${container} accepted incomplete restore arguments"
    fi
    docker exec -i "${container}" sh -c 'cat > /tmp/phase3-backup.sql' < "${dump_file}"
    docker exec "${container}" env MYSQL_PWD="${password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --execute 'DROP TABLE phase3_backup.sample'
    docker exec -i "${container}" env MYSQL_ADMIN_PASS="${password}" docker-lamp-restore --database phase3_backup < "${dump_file}"
    docker exec "${container}" env MYSQL_PWD="${password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --skip-column-names --batch --execute 'SELECT value_text FROM phase3_backup.sample' | grep -Fxq preserved
    docker exec "${container}" env MYSQL_PWD="${password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --execute 'DROP TABLE phase3_backup.sample'
    docker exec "${container}" env MYSQL_ADMIN_PASS="${password}" docker-lamp-restore --database phase3_backup --input /tmp/phase3-backup.sql
    docker exec "${container}" env MYSQL_PWD="${password}" mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
        --skip-column-names --batch --execute 'SELECT value_text FROM phase3_backup.sample' | grep -Fxq preserved
    docker rm --force "${container}" >/dev/null

    restricted_run "${invalid}" --tmpfs /var/lib/mysql:uid=1000,gid=1000,mode=0750 \
        --mount "type=bind,src=${tls_root},dst=/tls,readonly" -e "MYSQL_ADMIN_PASS=${password}" \
        -e APACHE_TLS_ENABLED=1 -e APACHE_TLS_CERT_FILE=/tls/cert.pem -e APACHE_TLS_KEY_FILE=/tls/missing.pem
    assert_container_failed "${invalid}"
    docker logs "${invalid}" 2>&1 | grep -Fq 'APACHE_TLS_KEY_FILE must name a readable regular file' \
        || fail "${invalid} did not report invalid TLS material"
    docker rm "${invalid}" >/dev/null
    remove_fixture_paths "${state_root}" "${app_root}" "${override_root}" "${tls_root}" "${dump_file}" "${stderr_file}"
}

build_php_artifacts
start_fresh_stack

for variant in "${VARIANTS[@]}"; do
    select_variant "${variant}"
    echo "Checking rootless runtime remediation for Ubuntu ${OS_VERSION} (${SERVICE})"

    wait_for "${SERVICE} Supervisor apache2" supervisor_running apache2
    wait_for "${SERVICE} Supervisor mysqld" supervisor_running mysqld
    wait_for "${SERVICE} Apache HTTP" http_page_available
    web_exec grep -Fx 'innodb-use-native-aio = 0' /run/mysql/docker-lamp.cnf
    apache_listener_present "$(compose ps -q "${SERVICE}")" 1F90
    ! apache_listener_present "$(compose ps -q "${SERVICE}")" 20FB \
        || fail "${SERVICE} enabled TLS port 8443 without APACHE_TLS_ENABLED=1"
    ! apache_listener_present "$(compose ps -q "${SERVICE}")" 01BB \
        || fail "${SERVICE} listened on forbidden port 443"
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
    run_supervisor_restart_fixture
    run_denied_mount_fixture
    [[ "${variant}" == 2204 ]] && run_mysql_native_aio_configuration_fixture
    run_disabled_php_overrides_fixture
    run_mysql_lifecycle_fixture
    run_mysql_bind_fixture
    run_mysql_credential_fixture
    run_phase3_transport_php_backup_fixture
    run_import_manifest_fixture
    [[ "${variant}" == 2204 ]] && run_import_failure_fixture
    [[ "${variant}" == 2204 ]] && run_ready_legacy_state_fixture
    [[ "${variant}" == 2204 ]] && run_unresponsive_init_shutdown_fixture
    [[ "${variant}" == 2204 ]] && run_term_during_import_fixture
    [[ "${variant}" == 2204 ]] && run_term_during_sql_import_fixture
    run_persistent_shutdown_fixture
    run_failure_fixture apache2
    run_failure_fixture mysqld
    run_failure_fixture watchdog
    run_failure_fixture control-channel
    [[ "${variant}" == 2204 ]] && run_forced_shutdown_fixture
    [[ "${variant}" == 2204 ]] && run_mysql_force_kill_fixture
done

echo "All rootless runtime remediation checks passed."
