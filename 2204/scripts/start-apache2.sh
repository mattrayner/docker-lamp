#!/usr/bin/env bash
set -euo pipefail

export APACHE_CONFDIR="${APACHE_CONFDIR:-/etc/apache2}"
source /etc/apache2/envvars
install -d -o "${APACHE_RUN_USER}" -g "${APACHE_RUN_GROUP}" -m 0755 "${APACHE_RUN_DIR}"
exec apache2 -DFOREGROUND
