#!/usr/bin/env bash

set -euo pipefail

readonly LAMP_UID=1000
readonly LAMP_GID=1000

runtime_error() {
    printf '%s\n' "docker-lamp runtime error: $*" >&2
    exit 1
}

validate_rootless_runtime() {
    local unsupported

    [[ "$(id -u)" == "${LAMP_UID}" && "$(id -g)" == "${LAMP_GID}" ]] \
        || runtime_error "the container must run as UID:GID ${LAMP_UID}:${LAMP_GID}"

    for unsupported in RUNTIME_UID RUNTIME_GID RUNTIME_PRIVILEGED_COMPAT RUNTIME_ALLOW_ROOT; do
        [[ -z "${!unsupported+x}" ]] \
            || runtime_error "${unsupported} is not supported; the runtime identity is fixed at ${LAMP_UID}:${LAMP_GID}"
    done

    [[ -r /app && -d /app ]] || runtime_error "/app must be a readable directory"
    [[ -d /var/lib/mysql && -w /var/lib/mysql ]] \
        || runtime_error "/var/lib/mysql must be a writable volume prepared for ${LAMP_UID}:${LAMP_GID}"
}

validate_apache_root() {
    local requested_root=${APACHE_ROOT:-/app}
    local resolved_root

    [[ "${requested_root}" == /* ]] || runtime_error "APACHE_ROOT must be an absolute path below /app"
    resolved_root=$(readlink -e -- "${requested_root}") \
        || runtime_error "APACHE_ROOT must name a readable directory below /app"
    case "${resolved_root}" in
        /app|/app/*) ;;
        *) runtime_error "APACHE_ROOT must be below /app" ;;
    esac
    [[ -d "${resolved_root}" && -r "${resolved_root}" && -x "${resolved_root}" ]] \
        || runtime_error "APACHE_ROOT must be a readable directory"
    export APACHE_ROOT="${resolved_root}"
}

ensure_runtime_directory() {
    local directory=$1

    mkdir -p "${directory}"
    [[ -w "${directory}" ]] \
        || runtime_error "${directory} must be a writable runtime mount prepared for ${LAMP_UID}:${LAMP_GID}"
}

validate_boolean() {
    local name=$1 default=$2 value
    value=${!name:-${default}}

    [[ "${value}" == 0 || "${value}" == 1 ]] \
        || runtime_error "${name} must be 0 or 1"
    printf '%s' "${value}"
}

validate_php_configuration() {
    PHP_USER_OVERRIDES_DISABLED=$(validate_boolean PHP_USER_OVERRIDES_DISABLED 0)
    XDEBUG_ENABLED=$(validate_boolean XDEBUG_ENABLED 0)
    export PHP_USER_OVERRIDES_DISABLED XDEBUG_ENABLED
    if [[ "${PHP_USER_OVERRIDES_DISABLED}" == 0 ]]; then
        [[ -d /etc/docker-lamp/php/conf.d && -r /etc/docker-lamp/php/conf.d && -x /etc/docker-lamp/php/conf.d ]] \
            || runtime_error "/etc/docker-lamp/php/conf.d must be a readable directory"
    fi
    [[ -d /etc/docker-lamp/php/xdebug-enabled && -r /etc/docker-lamp/php/xdebug-enabled ]] \
        || runtime_error "PHP Xdebug configuration is unavailable"
}

validate_apache_tls() {
    APACHE_TLS_ENABLED=$(validate_boolean APACHE_TLS_ENABLED 0)
    export APACHE_TLS_ENABLED
    if [[ "${APACHE_TLS_ENABLED}" == 0 ]]; then
        return
    fi
    : "${APACHE_TLS_CERT_FILE:?APACHE_TLS_CERT_FILE must be set when APACHE_TLS_ENABLED=1}"
    : "${APACHE_TLS_KEY_FILE:?APACHE_TLS_KEY_FILE must be set when APACHE_TLS_ENABLED=1}"
    [[ -f "${APACHE_TLS_CERT_FILE}" && -r "${APACHE_TLS_CERT_FILE}" ]] \
        || runtime_error "APACHE_TLS_CERT_FILE must name a readable regular file"
    [[ -f "${APACHE_TLS_KEY_FILE}" && -r "${APACHE_TLS_KEY_FILE}" ]] \
        || runtime_error "APACHE_TLS_KEY_FILE must name a readable regular file"
    [[ "${APACHE_TLS_CERT_FILE}" != *$'\n'* && "${APACHE_TLS_KEY_FILE}" != *$'\n'* \
        && "${APACHE_TLS_CERT_FILE}" != *'"'* && "${APACHE_TLS_KEY_FILE}" != *'"'* ]] \
        || runtime_error "TLS file paths contain unsupported characters"
    openssl x509 -noout -in "${APACHE_TLS_CERT_FILE}" >/dev/null 2>&1 \
        || runtime_error "APACHE_TLS_CERT_FILE is not a valid certificate"
    openssl pkey -noout -in "${APACHE_TLS_KEY_FILE}" >/dev/null 2>&1 \
        || runtime_error "APACHE_TLS_KEY_FILE is not a valid private key"
    [[ "$(openssl x509 -pubkey -noout -in "${APACHE_TLS_CERT_FILE}" | openssl pkey -pubin -outform DER | sha256sum)" \
        == "$(openssl pkey -pubout -outform DER -in "${APACHE_TLS_KEY_FILE}" | sha256sum)" ]] \
        || runtime_error "TLS certificate and private key do not match"
}

mysql_runtime_error() {
    # Never include control values in diagnostics: these controls commonly hold
    # credentials supplied by an orchestrator Secret.
    runtime_error "MySQL configuration: $*"
}

mysql_read_secret() {
    local value_name=$1 file_name=$2 value file
    local has_value=0 has_file=0

    [[ -n "${!value_name+x}" ]] && has_value=1
    [[ -n "${!file_name+x}" ]] && has_file=1
    (( has_value + has_file == 1 )) \
        || mysql_runtime_error "exactly one of ${value_name} or ${file_name} must be set"

    if (( has_value )); then
        value=${!value_name}
        [[ -n "${value}" ]] || mysql_runtime_error "${value_name} must not be empty"
    else
        file=${!file_name}
        [[ -n "${file}" && -f "${file}" && -r "${file}" ]] \
            || mysql_runtime_error "${file_name} must name a readable regular file"
        value=$(<"${file}")
        [[ -n "${value}" ]] || mysql_runtime_error "${file_name} must not name an empty file"
    fi
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] \
        || mysql_runtime_error "${value_name}/${file_name} must contain exactly one line"
    if (( has_file )); then
        php -r '$v = file_get_contents($argv[1]); exit(str_contains($v, "\0") ? 1 : 0);' "${file}" \
            || mysql_runtime_error "${file_name} must not contain NUL bytes"
    fi
    printf '%s' "${value}"
}

mysql_sql_literal() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\'/\\\'}
    printf "'%s'" "${value}"
}

mysql_defaults_value() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"' "${value}"
}

mysql_grant_database_target() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//%/\\%}
    value=${value//_/\\_}
    value=${value//\`/\`\`}
    printf '`%s`.*' "${value}"
}

mysql_validate_user_name() {
    local name=$1

    [[ "${name}" != *$'\n'* && "${name}" != *$'\r'* && "${name}" != *' ' \
        && ${#name} -le 32 && "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9_.%\$-]*$ ]] \
        || mysql_runtime_error "MYSQL_USER_NAME contains unsupported characters or exceeds MySQL length limits"
    case "${name}" in
        root|admin|mysql.sys|mysql.session|mysql.infoschema) mysql_runtime_error "MYSQL_USER_NAME is reserved" ;;
    esac
}

mysql_validate_database_name() {
    local database=$1

    # Database names are emitted both as quoted identifiers and as GRANT
    # targets. Keep the accepted grammar deliberately narrower than user
    # names: a period has SQL qualification semantics and is never valid here.
    [[ "${database}" != *$'\n'* && "${database}" != *$'\r'* && "${database}" != *' ' \
        && ${#database} -le 64 && "${database}" =~ ^[A-Za-z0-9][A-Za-z0-9_%\$-]*$ ]] \
        || mysql_runtime_error "MYSQL_USER_DB contains unsupported database identifier syntax or exceeds MySQL length limits"
    case "${database}" in
        mysql|sys|performance_schema|information_schema) mysql_runtime_error "MYSQL_USER_DB is reserved" ;;
    esac
}

mysql_validate_account_identifiers() {
    mysql_validate_user_name "$1"
    mysql_validate_database_name "$2"
}

mysql_validate_bind_address() {
    local bind_address=${MYSQL_BIND_ADDRESS:-127.0.0.1}

    local classification
    classification=$(php -r '
        $packed = inet_pton($argv[1]);
        if ($packed === false) exit(1);
        $mapped = strlen($packed) === 16 && substr($packed, 0, 12) === str_repeat("\0", 10) . "\xff\xff";
        if ($mapped) exit(2);
        $loopback = (strlen($packed) === 4 && ord($packed[0]) === 127) || $packed === inet_pton("::1");
        echo $loopback ? "localhost" : "%";
    ' "${bind_address}") || mysql_runtime_error "MYSQL_BIND_ADDRESS must be a supported non-mapped literal IPv4 or IPv6 address"
    export MYSQL_BIND_ADDRESS="${bind_address}"
    export MYSQL_ACCOUNT_HOST_POLICY="${classification}"
}

mysql_data_state() {
    local state_file=/var/lib/mysql/.docker-lamp-mysql-state state
    local -a entries=()

    if [[ -e "${state_file}" ]]; then
        state=$(<"${state_file}")
        case "${state}" in
            initializing)
                printf '%s\n' initializing
                return
                ;;
            ready)
                [[ -d /var/lib/mysql/mysql ]] || { printf '%s\n' inconsistent; return; }
                printf '%s\n' ready
                return
                ;;
            *)
                printf '%s\n' inconsistent
                return
                ;;
        esac
    fi

    if [[ -d /var/lib/mysql/mysql ]]; then
        printf '%s\n' legacy
        return
    fi
    shopt -s nullglob dotglob
    entries=(/var/lib/mysql/*)
    shopt -u nullglob dotglob
    (( ${#entries[@]} == 0 )) && printf '%s\n' fresh || printf '%s\n' inconsistent
}

mysql_write_state() {
    local state=$1 state_file=/var/lib/mysql/.docker-lamp-mysql-state temporary

    umask 077
    temporary="${state_file}.tmp.$$"
    printf '%s\n' "${state}" > "${temporary}"
    mv -f "${temporary}" "${state_file}"
}

mysql_preflight_first_run() {
    local input=/run/mysql/mysql-init-input manifest=/run/mysql/import-manifest import_file basename
    local admin_password app_password='' app_requested=0
    local control
    local LC_ALL=C

    admin_password=$(mysql_read_secret MYSQL_ADMIN_PASS MYSQL_ADMIN_PASS_FILE)
    for control in MYSQL_USER_NAME MYSQL_USER_DB MYSQL_USER_PASS MYSQL_USER_PASS_FILE CREATE_MYSQL_BASIC_USER_AND_DB; do
        [[ -z "${!control+x}" ]] || app_requested=1
    done
    if (( app_requested )); then
        [[ -n "${MYSQL_USER_NAME:-}" && -n "${MYSQL_USER_DB:-}" ]] \
            || mysql_runtime_error "an application account requires non-empty MYSQL_USER_NAME and MYSQL_USER_DB"
        mysql_validate_account_identifiers "${MYSQL_USER_NAME}" "${MYSQL_USER_DB}"
        app_password=$(mysql_read_secret MYSQL_USER_PASS MYSQL_USER_PASS_FILE)
        [[ -z "${CREATE_MYSQL_BASIC_USER_AND_DB+x}" ]] \
            || mysql_runtime_error "CREATE_MYSQL_BASIC_USER_AND_DB is not supported; provide the complete MYSQL_USER_* contract"
    fi

    : > "${manifest}"
    chmod 0600 "${manifest}"
    if [[ -e /docker-entrypoint-initdb.d ]]; then
        [[ -d /docker-entrypoint-initdb.d && -r /docker-entrypoint-initdb.d && -x /docker-entrypoint-initdb.d ]] \
            || mysql_runtime_error "/docker-entrypoint-initdb.d must be a readable searchable directory"
        shopt -s nullglob
        for import_file in /docker-entrypoint-initdb.d/*; do
            basename=${import_file##*/}
            [[ "${basename}" != *$'\n'* && -f "${import_file}" ]] \
                || mysql_runtime_error "initialization imports must be regular single-line filenames"
            case "${import_file}" in
                *.sql)
                    [[ -r "${import_file}" ]] || mysql_runtime_error "SQL initialization import is not readable"
                    ;;
                *.sql.gz)
                    [[ -r "${import_file}" ]] || mysql_runtime_error "compressed SQL initialization import is not readable"
                    gzip -t -- "${import_file}" >/dev/null 2>&1 \
                        || mysql_runtime_error "compressed SQL initialization import is invalid"
                    ;;
                *)
                    [[ -r "${import_file}" && -x "${import_file}" ]] \
                        || mysql_runtime_error "initialization import must be .sql, .sql.gz, or a readable executable file"
                    ;;
            esac
            printf '%s\n' "${import_file}" >> "${manifest}"
        done
        shopt -u nullglob
    fi

    umask 077
    {
        printf 'ADMIN_PASSWORD=%q\n' "${admin_password}"
        printf 'APP_REQUESTED=%q\n' "${app_requested}"
        printf 'APP_USER=%q\n' "${MYSQL_USER_NAME:-}"
        printf 'APP_DATABASE=%q\n' "${MYSQL_USER_DB:-}"
        printf 'APP_PASSWORD=%q\n' "${app_password}"
        printf 'ACCOUNT_HOST_POLICY=%q\n' "${MYSQL_ACCOUNT_HOST_POLICY}"
    } > "${input}"
    chmod 0600 "${input}"
    unset MYSQL_ADMIN_PASS MYSQL_ADMIN_PASS_FILE MYSQL_USER_PASS MYSQL_USER_PASS_FILE
}
