#!/usr/bin/env bash
set -euo pipefail

readonly STARTUP_GRACE_SECONDS=45
started_at=${SECONDS}
declare -A service_seen=([apache2]=0 [mysqld]=0)

service_alive() {
    local service=$1 pidfile=$2 pid

    if [[ ! -s "${pidfile}" ]]; then
        [[ "${service_seen[${service}]}" == 0 && $(( SECONDS - started_at )) -lt ${STARTUP_GRACE_SECONDS} ]] && return 0
        printf 'Critical service %s did not create %s.\n' "${service}" "${pidfile}" >&2
        return 1
    fi
    read -r pid < "${pidfile}"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
        service_seen[${service}]=1
        return 0
    fi
    printf 'Critical service %s is not running.\n' "${service}" >&2
    return 1
}

while :; do
    service_alive apache2 /run/lamp/apache2/apache2.pid || exit 1
    service_alive mysqld /run/mysql/mysqld.pid || exit 1
    sleep 1
done
