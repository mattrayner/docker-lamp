ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS build

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VERSION=8.5.12 \
    PHP_PREFIX=/opt/php

# This is the primary fingerprint of the official PHP release-signing key.
# Keep the keyring isolated and require this exact key before accepting a tarball.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) test "$(dpkg --print-architecture)" = amd64 ;; \
        arm64) test "$(dpkg --print-architecture)" = arm64 ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apache2 apache2-dev bison build-essential ca-certificates curl gpg gpg-agent gpgv \
        libcurl4-openssl-dev libfreetype6-dev libjpeg-dev libonig-dev \
        libpng-dev libsqlite3-dev libssl-dev libwebp-dev libxml2-dev libzip-dev pkg-config re2c \
        xz-utils zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL --retry 3 --output /tmp/php.tar.xz "https://www.php.net/distributions/php-8.5.12.tar.xz"; \
    curl -fsSL --retry 3 --output /tmp/php.tar.xz.asc "https://www.php.net/distributions/php-8.5.12.tar.xz.asc"; \
    expected_fingerprint='D95C03BC702BE9515344AE3374E44BC9067701A5'; \
    curl -fsSL --retry 3 --output /tmp/php-keyring.gpg https://www.php.net/distributions/php-keyring.gpg; \
    gpg --batch --import /tmp/php-keyring.gpg; \
    gpg --batch --with-colons --fingerprint "${expected_fingerprint}" | grep -Fq "fpr:::::::::${expected_fingerprint}:"; \
    gpg --batch --export "${expected_fingerprint}" > /tmp/php-release-keyring.gpg; \
    gpgv --status-fd=1 --keyring /tmp/php-release-keyring.gpg /tmp/php.tar.xz.asc /tmp/php.tar.xz \
        | grep -Fq "[GNUPG:] VALIDSIG ${expected_fingerprint}"; \
    tar -xJf /tmp/php.tar.xz -C /usr/src; \
    cd "/usr/src/php-${PHP_VERSION}"; \
    ./configure \
        --prefix="${PHP_PREFIX}" \
        --with-config-file-path="${PHP_PREFIX}/etc" \
        --with-config-file-scan-dir="${PHP_PREFIX}/etc/conf.d" \
        --with-apxs2=/usr/bin/apxs2 \
        --disable-cgi \
        --enable-cli \
        --enable-gd \
        --enable-mbstring \
        --enable-xml \
        --with-curl \
        --with-freetype \
        --with-jpeg \
        --with-mysqli=mysqlnd \
        --with-pdo-mysql=mysqlnd \
        --with-openssl \
        --with-sqlite3 \
        --with-webp \
        --with-zip \
        --with-zlib; \
    make -j"$(nproc)"; \
    make install; \
    install -d -m 0755 "${PHP_PREFIX}/etc/conf.d" /usr/local/share/php-build-metadata; \
    install -m 0644 php.ini-production "${PHP_PREFIX}/etc/php.ini"; \
    curl -fsSL --retry 3 --output /tmp/apcu-5.1.28.tgz "https://pecl.php.net/get/apcu-5.1.28.tgz"; \
    curl -fsSL --retry 3 --output /tmp/xdebug-3.5.3.tgz "https://pecl.php.net/get/xdebug-3.5.3.tgz"; \
    tar -xzf /tmp/apcu-5.1.28.tgz -C /tmp; \
    cd /tmp/apcu-5.1.28; \
    "${PHP_PREFIX}/bin/phpize"; \
    ./configure --with-php-config="${PHP_PREFIX}/bin/php-config"; \
    make -j"$(nproc)"; \
    make install; \
    tar -xzf /tmp/xdebug-3.5.3.tgz -C /tmp; \
    cd /tmp/xdebug-3.5.3; \
    "${PHP_PREFIX}/bin/phpize"; \
    ./configure --with-php-config="${PHP_PREFIX}/bin/php-config"; \
    make -j"$(nproc)"; \
    make install; \
    printf '%s\n' 'extension=apcu.so' 'apc.enable_cli=1' > "${PHP_PREFIX}/etc/conf.d/20-apcu.ini"; \
    printf '%s\n' 'zend_extension=xdebug.so' > "${PHP_PREFIX}/etc/conf.d/20-xdebug.ini"; \
    "${PHP_PREFIX}/bin/php" --version > /usr/local/share/php-build-metadata/php-version.txt; \
    "${PHP_PREFIX}/bin/php-config" --configure-options > /usr/local/share/php-build-metadata/configure-options.txt; \
    "${PHP_PREFIX}/bin/php" -m | sort > /usr/local/share/php-build-metadata/modules.txt; \
    test -f /usr/lib/apache2/modules/libphp.so; \
    "${PHP_PREFIX}/bin/php" -m | grep -qx apcu; \
    "${PHP_PREFIX}/bin/php" -m | grep -qx xdebug; \
    rm -rf /root/.gnupg /usr/src/php-* /tmp/apcu-5.1.28 /tmp/apcu-5.1.28.tgz /tmp/php.tar.xz /tmp/php.tar.xz.asc /tmp/php-keyring.gpg /tmp/php-release-keyring.gpg /tmp/xdebug-3.5.3 /tmp/xdebug-3.5.3.tgz

FROM scratch AS artifact

COPY --from=build /opt/php /opt/php
COPY --from=build /usr/lib/apache2/modules/libphp.so /usr/lib/apache2/modules/libphp.so
COPY --from=build /usr/local/share/php-build-metadata /usr/local/share/php-build-metadata
