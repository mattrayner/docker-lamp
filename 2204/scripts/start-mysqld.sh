#!/usr/bin/env bash
set -euo pipefail

install -d -o mysql -g mysql -m 0755 /run/mysqld
exec mysqld --user=mysql --console
