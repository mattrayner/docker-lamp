#!/usr/bin/env bash

readonly PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
readonly COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.test.yml"
readonly COMPOSE_PROJECT="ci"
readonly DEFAULT_VARIANTS=(2204 2404 2604)
if [[ -n "${TEST_VARIANTS:-}" ]]; then
    # Candidate CI supplies one release variant so it can test one immutable
    # final-image digest without starting unrelated services.
    read -r -a VARIANTS <<<"${TEST_VARIANTS}"
else
    VARIANTS=("${DEFAULT_VARIANTS[@]}")
fi

SERVICE=''
OS_VERSION=''
ADMIN_PASSWORD=''
WEB_PORT=''

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    echo "Docker Compose v2 (docker compose) or docker-compose is required." >&2
    exit 1
fi

compose() {
    "${COMPOSE[@]}" -f "${COMPOSE_FILE}" -p "${COMPOSE_PROJECT}" "$@"
}

select_variant() {
    local variant=$1

    case "${variant}" in
        2204)
            OS_VERSION='22.04'
            WEB_PORT='3020'
            ;;
        2404)
            OS_VERSION='24.04'
            WEB_PORT='3040'
            ;;
        2604)
            OS_VERSION='26.04'
            WEB_PORT='3060'
            ;;
        *)
            fail "unknown Ubuntu variant ${variant}"
            ;;
    esac

    SERVICE="web${variant}"
    ADMIN_PASSWORD="test-admin-password-${variant}"
}

dump_diagnostics() {
    echo >&2
    echo "===== Docker Compose status =====" >&2
    compose ps >&2 || true
    echo "===== Docker Compose logs =====" >&2
    # Initialization may log a supplied password. Keep diagnostics useful without
    # writing credentials to the terminal or CI logs.
    compose logs --no-color 2>&1 | sed -E 's/(admin password: ).*/\1[REDACTED]/' >&2 || true
}

test_failed() {
    local line=$1
    echo "Test failed at line ${line} for ${SERVICE:-the test stack}." >&2
    dump_diagnostics
}

fail() {
    echo "FAIL: $*" >&2
    return 1
}

wait_for() {
    local description=$1
    shift
    local attempts=60
    local attempt

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "$@" >/dev/null 2>&1; then
            echo "Ready: ${description}"
            return 0
        fi
        sleep 2
    done

    echo "Timed out after $((attempts * 2)) seconds waiting for ${description}." >&2
    dump_diagnostics
    return 1
}

start_fresh_stack() {
    local -a services=()
    local variant

    # The ci project is removed before each suite, so every variant starts with
    # an empty tmpfs-backed MySQL data directory.
    compose down --volumes --remove-orphans || true
    for variant in "${VARIANTS[@]}"; do
        services+=("web${variant}")
    done

    if [[ "${PREBUILT_FINAL_IMAGES:-0}" == 1 ]]; then
        : "${TEST_IMAGE:?TEST_IMAGE must identify the prebuilt final image.}"
        [[ ${#VARIANTS[@]} -eq 1 ]] || fail "prebuilt final-image tests require exactly one TEST_VARIANTS entry"
        compose pull "${services[@]}"
        compose up --detach --no-build --force-recreate --renew-anon-volumes "${services[@]}"
    else
        compose up --detach --build --force-recreate --renew-anon-volumes "${services[@]}"
    fi
}

build_php_artifacts() {
    local variant os_version artifact_image

    if [[ "${PREBUILT_PHP_ARTIFACTS:-0}" == 1 ]]; then
        : "${TEST_PHP_ARTIFACT_IMAGE:?TEST_PHP_ARTIFACT_IMAGE must identify the prebuilt PHP artifact.}"
        return
    fi

    : "${DOCKER_DEFAULT_PLATFORM:?DOCKER_DEFAULT_PLATFORM must be set (for example, linux/amd64 or linux/arm64).}"

    for variant in "${VARIANTS[@]}"; do
        case "${variant}" in
            2204) os_version='22.04' ;;
            2404) os_version='24.04' ;;
            2604) os_version='26.04' ;;
            *) fail "unknown Ubuntu variant ${variant}" ;;
        esac

        artifact_image="docker-lamp-php-artifact:${variant}"
        echo "Building ${artifact_image} for ${DOCKER_DEFAULT_PLATFORM}"
        docker build \
            --platform "${DOCKER_DEFAULT_PLATFORM}" \
            --file "${PROJECT_ROOT}/php-builder/Dockerfile" \
            --target artifact \
            --build-arg "UBUNTU_VERSION=${os_version}" \
            --build-arg 'PHP_VERSION=8.5.12' \
            --tag "${artifact_image}" \
            "${PROJECT_ROOT}"
    done
}

web_exec() {
    compose exec -T "${SERVICE}" "$@"
}

supervisor_running() {
    web_exec supervisorctl status "$1" | grep -Eq "^$1[[:space:]]+RUNNING"
}

http_page_available() {
    curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:${WEB_PORT}/" \
        | grep -q "Welcome to"
}

install_test_fixtures() {
    web_exec sh -ec '
        test -r /test-fixtures/rewrite-check/.htaccess
        test -r /test-fixtures/static-check.txt
        test -r /test-fixtures/runtime-check.php
    '
}

mysql_admin_login() {
    web_exec env MYSQL_PWD="${ADMIN_PASSWORD}" mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin \
        --connect-timeout=5 --execute "SELECT 1"
}

# A separate container on the Compose network verifies a true remote TCP
# connection rather than a local MySQL socket in the database container.
remote_mysql() {
    compose run --rm --no-deps -T --env "MYSQL_PWD=${ADMIN_PASSWORD}" "${SERVICE}" \
        mysql --protocol=TCP -h "${SERVICE}" -P 3306 -uadmin --connect-timeout=5 "$@"
}

test_operating_system() {
    echo "Checking Ubuntu ${OS_VERSION}"
    web_exec bash -ec ". /etc/os-release; test \"\$ID\" = ubuntu; test \"\$VERSION_ID\" = \"${OS_VERSION}\""
}

test_cli_php() {
    local extension
    local -a required_extensions=(apcu curl gd mbstring mysqli pdo_mysql xml zip xdebug)

    echo "Checking PHP >= 8.5.12 CLI and required extensions"
    web_exec php -r 'exit(version_compare(PHP_VERSION, "8.5.12", ">=") ? 0 : 1);'
    for extension in "${required_extensions[@]}"; do
        web_exec php -m | tr '[:upper:]' '[:lower:]' | grep -Fxq "${extension}" \
            || fail "PHP CLI extension ${extension} is not loaded"
    done
}

test_apache_php_and_rewrite() {
    local response apache_php_version

    echo "Checking Apache, mod_rewrite, and Apache PHP >= 8.5.12"
    web_exec bash -ec '
        export APACHE_CONFDIR=/etc/apache2
        . /etc/apache2/envvars
        export APACHE_RUN_USER=lamp
        export APACHE_RUN_GROUP="$(id -gn lamp)"
        export APACHE_RUN_DIR=/run/lamp/apache2
        export APACHE_PID_FILE=/run/lamp/apache2/apache2.pid
        export APACHE_LOCK_DIR=/run/lamp/apache2
        export APACHE_LOG_DIR=/run/lamp/apache2
        apache2 -M
    ' | grep -Eq 'rewrite_module.*shared'

    response=$(curl --fail --silent --show-error --max-time 10 \
        "http://127.0.0.1:${WEB_PORT}/rewrite-check/php85")
    if [[ "${response}" =~ php=([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        apache_php_version=${BASH_REMATCH[1]}
    else
        fail "Apache did not report its PHP version"
    fi
    web_exec php -r 'exit(version_compare($argv[1], "8.5.12", ">=") ? 0 : 1);' "${apache_php_version}" \
        || fail "Apache did not execute PHP >= 8.5.12 (reported ${apache_php_version})"
    [[ "${response}" == *"extensions=ok"* ]] || fail "Apache PHP extensions are not loaded"
}

test_static_serving() {
    local response

    echo "Checking Apache static-file serving"
    response=$(curl --fail --silent --show-error --max-time 10 \
        "http://127.0.0.1:${WEB_PORT}/static-check.txt")
    [[ "${response}" == 'docker-lamp static fixture' ]] \
        || fail "Apache did not serve the static fixture"
}

test_php_runtime_dependencies() {
    local response
    local expected
    local -a expected_results=(
        'upload_max_filesize=10M'
        'post_max_size=10M'
        'timezone=Europe/London'
        'apcu=ok'
        'curl=ok'
        'gd=ok'
        'mbstring=ok'
        'xml=ok'
        'zip=ok'
        'mysqli=ok'
        'pdo_mysql=ok'
    )

    echo "Checking mod_php configuration and PHP runtime dependencies"
    if ! response=$(curl --fail --silent --show-error --max-time 15 \
        "http://127.0.0.1:${WEB_PORT}/runtime-check.php"); then
        fail "Apache PHP runtime dependency check failed"
    fi

    for expected in "${expected_results[@]}"; do
        [[ "${response}" == *"${expected}"* ]] \
            || fail "Apache PHP runtime check did not report ${expected}"
    done
}

test_no_php7() {
    echo "Checking that PHP 7 is absent"
    ! web_exec bash -ec 'command -v php7 || command -v php7.4 || dpkg-query -W -f="${db:Status-Abbrev} ${binary:Package}\n" "php7*" 2>/dev/null | grep -Eq "^ii "'
}

test_supervisor() {
    echo "Checking Supervisor processes"
    supervisor_running apache2
    supervisor_running mysqld
}

test_mysql() {
    local version

    echo "Checking MySQL 9.7"
    version=$(web_exec env MYSQL_PWD="${ADMIN_PASSWORD}" mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin \
        --skip-column-names --batch --execute 'SELECT VERSION()')
    [[ "${version}" =~ ^9\.7\. ]] || fail "expected MySQL 9.7, got ${version}"
}

test_mysql_utf8mb4_and_restore() {
    echo "Checking MySQL utf8mb4 configuration, emoji storage, and dump restore"
    web_exec env MYSQL_PWD="${ADMIN_PASSWORD}" bash -ec '
        set -e
        database=dependency_restore_check
        dump_file=$(mktemp)
        trap "rm -f \"${dump_file}\"" EXIT

        mysqladmin --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin ping --silent >/dev/null
        test "$(mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --skip-column-names --batch \
            --execute "SELECT @@character_set_server")" = utf8mb4

        mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --default-character-set=utf8mb4 \
            --execute "DROP DATABASE IF EXISTS ${database}; CREATE DATABASE ${database} CHARACTER SET utf8mb4; \
                CREATE TABLE ${database}.emoji (value_text VARCHAR(16)) CHARACTER SET utf8mb4; \
                INSERT INTO ${database}.emoji VALUES ('\''😀'\'');"
        mysqldump --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --default-character-set=utf8mb4 \
            --single-transaction --set-gtid-purged=OFF --databases "${database}" > "${dump_file}"
        mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --execute "DROP DATABASE ${database}"
        mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --default-character-set=utf8mb4 < "${dump_file}"
        test "$(mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --default-character-set=utf8mb4 \
            --skip-column-names --batch --execute "SELECT value_text FROM ${database}.emoji")" = "😀"
        mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin --execute "DROP DATABASE ${database}"
    '
}

test_xdebug_coverage() {
    echo "Checking Xdebug callable code-coverage support"
    web_exec env XDEBUG_MODE=coverage php -d xdebug.mode=coverage -r '
        if (!function_exists("xdebug_start_code_coverage")) {
            exit(1);
        }
        xdebug_start_code_coverage();
        $coveredLine = __LINE__ + 1;
        $value = 42;
        $coverage = xdebug_get_code_coverage();
        xdebug_stop_code_coverage();
        exit($value === 42 && $coverage ? 0 : 1);
    '
}

test_composer() {
    echo "Checking Composer version and project validation"
    web_exec bash -ec '
        set -e
        working_directory=$(mktemp -d)
        trap "rm -rf \"${working_directory}\"" EXIT
        cd "${working_directory}"
        printf "%s\\n" '\''{"name":"docker-lamp/dependency-check","description":"Local Composer validation test","license":"MIT","require":{}}'\'' > composer.json
        composer --version | grep -Eq "^Composer version 2\\.10\\.3 "
        COMPOSER_DISABLE_NETWORK=1 COMPOSER_ROOT_VERSION=1.0.0 composer validate --no-check-publish
    '
}

test_openssl() {
    echo "Checking OpenSSL local key generation and signature verification"
    web_exec bash -ec '
        set -e
        working_directory=$(mktemp -d)
        trap "rm -rf \"${working_directory}\"" EXIT
        cd "${working_directory}"
        printf "docker-lamp local openssl check" > payload
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out private.pem >/dev/null 2>&1
        openssl pkey -in private.pem -pubout -out public.pem >/dev/null 2>&1
        openssl dgst -sha256 -sign private.pem -out payload.sig payload
        openssl dgst -sha256 -verify public.pem -signature payload.sig payload | grep -Fx "Verified OK"
    '
}

test_remote_admin_login() {
    echo "Checking default loopback-only MySQL policy and unpublished host port"
    ! remote_mysql --execute 'SELECT 1' >/dev/null 2>&1 \
        || fail "${SERVICE} accepted a peer-network MySQL connection with loopback binding"
    [[ "$(docker inspect --format '{{json .NetworkSettings.Ports}}' "$(compose ps -q "${SERVICE}")")" != *'3306/tcp'* ]] \
        || fail "${SERVICE} publishes MySQL to the host by default"
}

test_supervisor_apache_recovery() {
    echo "Checking Supervisor Apache restart and HTTP recovery"
    web_exec supervisorctl restart apache2 >/dev/null
    wait_for "${SERVICE} Apache after Supervisor restart" supervisor_running apache2
    wait_for "${SERVICE} HTTP after Supervisor restart" http_page_available
}

test_adminer() {
    local adminer_url="http://127.0.0.1:${WEB_PORT}/adminer/"
    local cookie_jar response login_token

    cookie_jar=$(mktemp)
    response=$(mktemp)

    echo "Checking Adminer login form and authenticated session"
    if ! curl --fail --silent --show-error --max-time 10 \
        --cookie-jar "${cookie_jar}" --output "${response}" "${adminer_url}"; then
        rm -f "${cookie_jar}" "${response}"
        return 1
    fi

    if ! grep -Eq '<form[^>]*>' "${response}" \
        || ! grep -Eq "name=[\"']auth\\[username\\][\"']" "${response}" \
        || ! grep -Eq "name=[\"']auth\\[password\\][\"']" "${response}" \
        || ! grep -q 'localhost' "${response}"; then
        rm -f "${cookie_jar}" "${response}"
        fail "Adminer did not serve the expected localhost-prefilled login form"
    fi

    # Adminer also renders a token for non-login requests. Select the token from
    # the form containing the username field rather than the first token on page.
    login_token=$(perl -0777 -ne '
        while (m{<form\b[^>]*>(.*?)</form\s*>}sig) {
            my $form = $1;
            next unless $form =~ m{<input\b(?=[^>]*\bname\s*=\s*(["\x27])auth\[username\]\1)[^>]*>}i;
            if ($form =~ m{<input\b(?=[^>]*\bname\s*=\s*(["\x27])token\1)(?=[^>]*\bvalue\s*=\s*(["\x27])(.*?)\2)[^>]*>}is) {
                print $3;
                exit;
            }
        }
    ' "${response}")
    if [[ -z "${login_token}" ]]; then
        rm -f "${cookie_jar}" "${response}"
        fail "Adminer login form did not include a CSRF token"
    fi

    if ! curl --fail --silent --show-error --max-time 10 --location \
        --cookie "${cookie_jar}" --cookie-jar "${cookie_jar}" \
        --data-urlencode 'auth[driver]=server' \
        --data-urlencode 'auth[server]=localhost' \
        --data-urlencode 'auth[username]=admin' \
        --data-urlencode "auth[password]=${ADMIN_PASSWORD}" \
        --data-urlencode "token=${login_token}" \
        --output "${response}" "${adminer_url}"; then
        rm -f "${cookie_jar}" "${response}"
        return 1
    fi

    if ! grep -qi 'logout' "${response}"; then
        rm -f "${cookie_jar}" "${response}"
        fail "Adminer did not create an authenticated admin session"
    fi

    rm -f "${cookie_jar}" "${response}"
}

test_fresh_container() {
    local database="docker_lamp_freshness_check"

    echo "Checking fresh-container database initialization"
    web_exec env MYSQL_PWD="${ADMIN_PASSWORD}" mysql --protocol=TCP -h 127.0.0.1 -P 3306 -uadmin \
        --execute "CREATE DATABASE ${database}"
    compose up --detach --force-recreate --renew-anon-volumes "${SERVICE}"
    wait_for "${SERVICE} MySQL after recreation" mysql_admin_login

    if remote_mysql --skip-column-names --batch --execute \
        "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${database}'" \
        | grep -Fxq "${database}"; then
        fail "MySQL data persisted after recreating the tmpfs-backed test container"
    fi

    mysql_admin_login
}
