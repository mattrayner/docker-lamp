#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/etc/apache2/envvars
export APACHE_CONFDIR=/etc/apache2
source /etc/apache2/envvars

export APACHE_RUN_USER=lamp
export APACHE_RUN_GROUP="$(id -gn lamp)"
export APACHE_RUN_DIR=/run/lamp/apache2
export APACHE_PID_FILE=/run/lamp/apache2/apache2.pid
export APACHE_LOCK_DIR=/run/lamp/apache2
export APACHE_LOG_DIR=/run/lamp/apache2
export APACHE_ROOT="${APACHE_ROOT:-/app}"
export PHP_INI_SCAN_DIR=/opt/php/etc/conf.d:/run/lamp/php/conf.d
if [[ "${PHP_USER_OVERRIDES_DISABLED:-0}" != 1 ]]; then
    export PHP_INI_SCAN_DIR="${PHP_INI_SCAN_DIR}:/etc/docker-lamp/php/conf.d"
fi
if [[ "${XDEBUG_ENABLED:-0}" == 1 ]]; then
    export PHP_INI_SCAN_DIR="${PHP_INI_SCAN_DIR}:/etc/docker-lamp/php/xdebug-enabled"
fi

exec apache2 -DFOREGROUND
