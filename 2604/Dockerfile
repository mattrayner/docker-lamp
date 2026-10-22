ARG PHP_ARTIFACT_IMAGE=mattrayner/lamp-php:8.5.12-ubuntu26.04-r1
FROM ${PHP_ARTIFACT_IMAGE} AS php-artifact

FROM ubuntu:26.04

ARG TARGETARCH

LABEL org.opencontainers.image.title="docker-lamp" \
      org.opencontainers.image.description="Ubuntu 26.04 LTS LAMP image with PHP 8.5 and MySQL 9.7 LTS" \
      org.opencontainers.image.base.name="ubuntu:26.04" \
      io.raynerdigital.php.version="8.5" \
      io.raynerdigital.mysql.version="9.7 LTS"

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=8.5.12 \
    MYSQL_VERSION=9.7 \
    PHP_UPLOAD_MAX_FILESIZE=10M \
    PHP_POST_MAX_SIZE=10M \
    PHP_TIMEZONE=Europe/London \
    APACHE_ROOT=/app \
    PHP_INI_SCAN_DIR=/opt/php/etc/conf.d:/run/lamp/php/conf.d \
    PATH=/usr/local/bin:/opt/php/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2 \
        ca-certificates \
        curl \
        libaio1t64 \
        libcurl4t64 \
        libfreetype6 \
        libjpeg-turbo8 \
        libncurses6 \
        libnuma1 \
        libonig5 \
        libpng16-16t64 \
        libsqlite3-0 \
        libssl3t64 \
        libtinfo6 \
        libwebp7 \
        libxml2-16 \
        libzip5 \
        openssl \
        supervisor \
        xz-utils \
        zlib1g \
    && libaio_dir="$(dirname /usr/lib/*-linux-gnu/libaio.so.1t64)" \
    && ln -s libaio.so.1t64 "${libaio_dir}/libaio.so.1" \
    && case "${TARGETARCH}" in \
        amd64) mysql_url='https://cdn.mysql.com/Downloads/MySQL-9.7/mysql-9.7.4-linux-glibc2.28-x86_64.tar.xz'; mysql_md5='dbc4f76f6bedab22a136af9ed846b2cf'; mysql_dir='mysql-9.7.4-linux-glibc2.28-x86_64' ;; \
        arm64) mysql_url='https://cdn.mysql.com/Downloads/MySQL-9.7/mysql-9.7.4-linux-glibc2.28-aarch64.tar.xz'; mysql_md5='6c1ede742c21d4a4a74cc96b66a543e5'; mysql_dir='mysql-9.7.4-linux-glibc2.28-aarch64' ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 3 --output /tmp/mysql.tar.xz "${mysql_url}" \
    && echo "${mysql_md5}  /tmp/mysql.tar.xz" | md5sum -c - \
    && tar -xJf /tmp/mysql.tar.xz -C /usr/local \
    && ln -s "/usr/local/${mysql_dir}" /usr/local/mysql \
    && ln -s /usr/local/mysql/bin/mysqld /usr/local/bin/mysqld \
    && ln -s /usr/local/mysql/bin/mysql /usr/local/bin/mysql \
    && ln -s /usr/local/mysql/bin/mysqladmin /usr/local/bin/mysqladmin \
    && ln -s /usr/local/mysql/bin/mysqldump /usr/local/bin/mysqldump \
    && (getent group 1000 >/dev/null || groupadd --gid 1000 lamp) \
    && useradd --non-unique --uid 1000 --gid 1000 --home-dir /nonexistent --shell /usr/sbin/nologin lamp \
    && curl -fsSL --retry 3 --output /tmp/composer.phar \
       https://getcomposer.org/download/2.10.3/composer.phar \
    && echo '7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6  /tmp/composer.phar' \
       | sha256sum -c - \
    && install -m 0755 /tmp/composer.phar /usr/local/bin/composer \
    && rm /tmp/composer.phar /tmp/mysql.tar.xz \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
    && rm -rf /var/lib/apt/lists/* /var/lib/mysql

COPY --from=php-artifact /opt/php /opt/php
COPY --from=php-artifact /usr/lib/apache2/modules/libphp.so /usr/lib/apache2/modules/libphp.so
COPY --from=php-artifact /usr/local/share/php-build-metadata /usr/local/share/php-build-metadata

COPY --chmod=0644 2604/config/apache-site.conf /etc/apache2/sites-available/docker-lamp.conf
COPY --chmod=0644 2604/config/adminer-index.php /usr/local/share/adminer/index.php
COPY --chmod=0644 2604/config/supervisord.conf /etc/supervisor/supervisord.conf
COPY --chmod=755 runtime/entrypoint.sh /run.sh
COPY --chmod=755 runtime/lib.sh /usr/local/lib/docker-lamp/runtime.sh
COPY --chmod=755 runtime/mysql-init.sh /usr/local/bin/mysql-init
COPY --chmod=755 runtime/start-apache2.sh /usr/local/bin/start-apache2
COPY --chmod=755 runtime/start-mysqld.sh /usr/local/bin/start-mysqld
COPY --chmod=755 runtime/supervisor-watchdog.sh /usr/local/bin/supervisor-watchdog
COPY --chmod=755 runtime/php /usr/local/bin/php
COPY --chmod=755 runtime/docker-lamp-backup /usr/local/bin/docker-lamp-backup
COPY --chmod=755 runtime/docker-lamp-restore /usr/local/bin/docker-lamp-restore

RUN printf '%s\n' 'LoadModule php_module /usr/lib/apache2/modules/libphp.so' > /etc/apache2/mods-available/php8.5.load \
    && rm -f /opt/php/etc/conf.d/*xdebug*.ini \
    && printf '%s\n' \
        '<IfModule php_module>' \
        '    <FilesMatch "\\.php$">' \
        '        SetHandler application/x-httpd-php' \
        '    </FilesMatch>' \
        '    <FilesMatch "\\.phps$">' \
        '        Require all denied' \
        '    </FilesMatch>' \
        '    DirectoryIndex index.php index.html' \
        '</IfModule>' > /etc/apache2/mods-available/php8.5.conf \
    && a2dismod mpm_event \
    && a2enmod mpm_prefork php8.5 rewrite ssl \
    && printf '%s\n' 'ServerName localhost' > /etc/apache2/conf-available/docker-lamp-servername.conf \
    && a2enconf docker-lamp-servername \
    && a2dissite 000-default \
    && a2ensite docker-lamp \
    && printf '%s\n' 'Listen 8080' > /etc/apache2/ports.conf \
    && install -d -o 1000 -g 1000 -m 0755 /run/lamp /run/mysql /var/lib/mysql /app /etc/docker-lamp/php/conf.d /etc/docker-lamp/php/xdebug-enabled \
    && printf '%s\n' 'zend_extension=xdebug.so' > /etc/docker-lamp/php/xdebug-enabled/20-xdebug.ini \
    && rm -rf /var/www/html \
    && ln -s /app /var/www/html

RUN install -d -m 0755 /usr/local/share/adminer \
    && curl -fsSL --retry 3 --output /usr/local/share/adminer/adminer.php \
       https://github.com/vrana/adminer/releases/download/v6.1.2/adminer-6.1.2-mysql.php \
    && echo '30d600b5d8750600b7cf7d8e4652f27d3bcd23ca6c9e1e6399a9b4a274fd7c0e  /usr/local/share/adminer/adminer.php' \
       | sha256sum -c - \
    && chmod 0644 /usr/local/share/adminer/adminer.php /usr/local/share/adminer/index.php

COPY --chown=0:0 app/ /app/
RUN chown -R 0:0 /app && chmod -R a-w /app

VOLUME ["/var/lib/mysql"]

EXPOSE 8080 8443 3306

USER 1000:1000
CMD ["/run.sh"]
