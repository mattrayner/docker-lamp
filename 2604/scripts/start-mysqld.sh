#!/usr/bin/env bash
set -euo pipefail

install -d -o mysql -g mysql -m 0755 /run/mysqld
exec mysqld --defaults-file=/etc/mysql/docker-lamp.cnf --user=mysql --console
