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
    printf '%s' "${value}"
}

mysql_validate_bind_address() {
    local bind_address=${MYSQL_BIND_ADDRESS:-127.0.0.1}

    php -r 'exit(filter_var($argv[1], FILTER_VALIDATE_IP) === false ? 1 : 0);' "${bind_address}" \
        || mysql_runtime_error "MYSQL_BIND_ADDRESS must be a supported literal IPv4 or IPv6 address"
    export MYSQL_BIND_ADDRESS="${bind_address}"
    case "${bind_address}" in
        127.*|::1) export MYSQL_ACCOUNT_HOST_POLICY=localhost ;;
        *) export MYSQL_ACCOUNT_HOST_POLICY=% ;;
    esac
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
    local input=/run/mysql/mysql-init-input
    local admin_password app_password='' app_requested=0
    local control

    admin_password=$(mysql_read_secret MYSQL_ADMIN_PASS MYSQL_ADMIN_PASS_FILE)
    for control in MYSQL_USER_NAME MYSQL_USER_DB MYSQL_USER_PASS MYSQL_USER_PASS_FILE CREATE_MYSQL_BASIC_USER_AND_DB; do
        [[ -z "${!control+x}" ]] || app_requested=1
    done
    if (( app_requested )); then
        [[ -n "${MYSQL_USER_NAME:-}" && -n "${MYSQL_USER_DB:-}" ]] \
            || mysql_runtime_error "an application account requires non-empty MYSQL_USER_NAME and MYSQL_USER_DB"
        app_password=$(mysql_read_secret MYSQL_USER_PASS MYSQL_USER_PASS_FILE)
        [[ -z "${CREATE_MYSQL_BASIC_USER_AND_DB+x}" ]] \
            || mysql_runtime_error "CREATE_MYSQL_BASIC_USER_AND_DB is not supported; provide the complete MYSQL_USER_* contract"
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
