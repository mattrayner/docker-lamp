#!/usr/bin/env bash
set -euo pipefail

export APACHE_CONFDIR="${APACHE_CONFDIR:-/etc/apache2}"
source /etc/apache2/envvars
exec apache2 -DFOREGROUND
