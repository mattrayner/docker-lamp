FROM ubuntu:26.04

LABEL org.opencontainers.image.title="docker-lamp" \
      org.opencontainers.image.description="Ubuntu 26.04 LTS LAMP image with PHP 8.5 and MySQL 9.7 LTS" \
      org.opencontainers.image.base.name="ubuntu:26.04" \
      io.raynerdigital.php.version="8.5" \
      io.raynerdigital.mysql.version="9.7 LTS"

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=8.5 \
    MYSQL_VERSION=9.7 \
    PHP_UPLOAD_MAX_FILESIZE=10M \
    PHP_POST_MAX_SIZE=10M \
    PHP_TIMEZONE=Europe/London

# Install repository bootstrap tools first. Both third-party repositories use
# dedicated keyrings; apt-key is intentionally not used.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://packages.sury.org/php/apt.gpg \
       | gpg --batch --yes --dearmor -o /etc/apt/keyrings/sury-php.gpg \
    && curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 \
       | gpg --batch --yes --dearmor -o /etc/apt/keyrings/mysql.gpg \
    && . /etc/os-release \
    && printf '%s\n' "deb [signed-by=/etc/apt/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${VERSION_CODENAME} main" \
       > /etc/apt/sources.list.d/sury-php.list \
    && printf '%s\n' "deb [signed-by=/etc/apt/keyrings/mysql.gpg] https://repo.mysql.com/apt/ubuntu/ ${VERSION_CODENAME} mysql-9.7-lts mysql-tools" \
       > /etc/apt/sources.list.d/mysql-9.7-lts.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       apache2 \
       libapache2-mod-php8.5 \
       mysql-client \
       mysql-community-server \
       openssl \
       php8.5-apcu \
       php8.5-cli \
       php8.5-curl \
       php8.5-gd \
       php8.5-mbstring \
       php8.5-mysql \
       php8.5-xml \
       php8.5-xdebug \
       php8.5-zip \
       supervisor \
    && a2enmod rewrite \
    && curl -fsSL --retry 3 --output /tmp/composer.phar \
       https://getcomposer.org/download/2.10.3/composer.phar \
    && echo '7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6  /tmp/composer.phar' \
       | sha256sum -c - \
    && install -m 0755 /tmp/composer.phar /usr/local/bin/composer \
    && rm /tmp/composer.phar \
    && rm -rf /var/lib/apt/lists/* /var/lib/mysql

COPY --chmod=0644 2604/config/apache-site.conf /etc/apache2/sites-available/docker-lamp.conf
COPY --chmod=0644 2604/config/adminer-index.php /usr/local/share/adminer/index.php
COPY --chmod=0644 2604/config/supervisord.conf /etc/supervisor/supervisord.conf
COPY --chmod=755 2604/scripts/entrypoint.sh /run.sh
COPY --chmod=755 2604/scripts/mysql-init.sh /usr/local/bin/mysql-init
COPY --chmod=755 2604/scripts/start-apache2.sh /usr/local/bin/start-apache2
COPY --chmod=755 2604/scripts/start-mysqld.sh /usr/local/bin/start-mysqld

RUN printf '%s\n' 'ServerName localhost' > /etc/apache2/conf-available/docker-lamp-servername.conf \
    && a2enconf docker-lamp-servername \
    && a2dissite 000-default \
    && a2ensite docker-lamp \
    && install -d -o mysql -g mysql -m 0755 /run/mysqld /var/log/supervisor \
    && install -d -o www-data -g www-data -m 0755 /app \
    && rm -rf /var/www/html \
    && ln -s /app /var/www/html

RUN install -d -m 0755 /usr/local/share/adminer \
    && curl -fsSL --retry 3 --output /usr/local/share/adminer/adminer.php \
       https://github.com/vrana/adminer/releases/download/v6.1.2/adminer-6.1.2-mysql.php \
    && echo '30d600b5d8750600b7cf7d8e4652f27d3bcd23ca6c9e1e6399a9b4a274fd7c0e  /usr/local/share/adminer/adminer.php' \
       | sha256sum -c - \
    && chown root:root /usr/local/share/adminer/adminer.php /usr/local/share/adminer/index.php \
    && chmod 0644 /usr/local/share/adminer/adminer.php /usr/local/share/adminer/index.php

COPY --chown=www-data:www-data app/ /app/

VOLUME ["/app", "/var/lib/mysql"]

EXPOSE 80 3306

CMD ["/run.sh"]
