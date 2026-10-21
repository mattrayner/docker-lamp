#!/usr/bin/env bash
set -euo pipefail

configure_php() {
    local ini_contents
    ini_contents="; Generated at container start from docker-lamp environment variables
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}
post_max_size = ${PHP_POST_MAX_SIZE}
date.timezone = ${PHP_TIMEZONE}"
    printf '%s\n' "${ini_contents}" > /etc/php/8.5/apache2/conf.d/99-docker-lamp.ini
    printf '%s\n' "${ini_contents}" > /etc/php/8.5/cli/conf.d/99-docker-lamp.ini
}

configure_apache_root() {
    if [[ -n "${APACHE_ROOT:-}" ]]; then
        echo "Using /app/${APACHE_ROOT} as the Apache document root"
        rm -f /var/www/html
        ln -s "/app/${APACHE_ROOT}" /var/www/html
    fi
}

configure_mysql() {
    install -d -o mysql -g mysql -m 0755 /run/mysqld
    install -d -o mysql -g mysql -m 0750 /var/lib/mysql
    chown -R mysql:mysql /var/lib/mysql
    cat > /etc/mysql/conf.d/docker-lamp.cnf <<'EOF'
[mysqld]
bind-address = 0.0.0.0
socket = /run/mysqld/mysqld.sock
pid-file = /run/mysqld/mysqld.pid
character-set-server = utf8mb4
collation-server = utf8mb4_0900_ai_ci
EOF
}

configure_php
configure_apache_root
configure_mysql

if [[ ! -d /var/lib/mysql/mysql ]]; then
    /usr/local/bin/mysql-init
fi

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
