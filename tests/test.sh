#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_helpers.sh
source "${SCRIPT_DIR}/_helpers.sh"

trap 'test_failed "$LINENO"' ERR

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
