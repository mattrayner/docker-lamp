#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"${SCRIPT_DIR}/test-compose-project-name.sh"
"${SCRIPT_DIR}/test-kubernetes-manifest.sh"
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

trap 'test_failed "$LINENO"' ERR

build_php_artifacts
start_fresh_stack

for variant in "${VARIANTS[@]}"; do
    select_variant "${variant}"
    echo "Testing Ubuntu ${OS_VERSION} / PHP 8.5 / MySQL 9.7 (${SERVICE})"

    # Bounded readiness checks produce Compose diagnostics instead of allowing a
    # broken image startup to leave CI in an unbounded retry loop.
    wait_for "${SERVICE} Supervisor apache2" supervisor_running apache2
    wait_for "${SERVICE} Supervisor mysqld" supervisor_running mysqld
    wait_for "${SERVICE} Apache HTTP" http_page_available
    wait_for "${SERVICE} MySQL admin login" mysql_admin_login

    install_test_fixtures
    test_operating_system
    test_cli_php
    test_apache_php_and_rewrite
    test_static_serving
    test_php_runtime_dependencies
    test_no_php7
    test_supervisor
    test_mysql
    test_mysql_utf8mb4_and_restore
    test_xdebug_coverage
    test_composer
    test_openssl
    test_supervisor_apache_recovery
    test_remote_admin_login
    test_adminer
    test_fresh_container

    echo "All ${OS_VERSION} image checks passed."
done

if [[ "${RUN_ROOTLESS_RUNTIME_TESTS:-0}" == 1 ]]; then
    # MySQL reserves native-AIO slots per running service.  Tear down the
    # completed behavioral stack before starting the separate rootless stack,
    # otherwise the six concurrent variant services can exhaust the host-wide
    # AIO limit and make a healthy matrix fail during MySQL initialization.
    compose down --volumes --remove-orphans
    # Keep the nested suite isolated: it rebuilds and tears down its own stack.
    TEST_COMPOSE_PROJECT="${COMPOSE_PROJECT}-rootless" "${SCRIPT_DIR}/test-rootless-runtime.sh"
fi
