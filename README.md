# Docker-LAMP

Docker-LAMP packages Apache, MySQL, and PHP in one development image. The current image line provides PHP 8.5.12 and MySQL 9.7 LTS on Ubuntu 22.04, 24.04, and 26.04. PHP 8.5.12 is the minimum supported PHP version for this image line because earlier versions have security issues.

## Image versions

| Image | Ubuntu | PHP | MySQL | Database UI | Support |
| --- | --- | --- | --- | --- | --- |
| `latest-2204-php8.5` (planned release) | 22.04 LTS | 8.5.12 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2404-php8.5` (planned release) | 24.04 LTS | 8.5.12 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2604-php8.5` (planned release) | 26.04 LTS | 8.5.12 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2004-php8` | 20.04 LTS | 8.0 | 8.0 | phpMyAdmin 5.1.1 | Unsupported legacy image |
| `latest-2004-php7` | 20.04 LTS | 7.4 | 8.0 | phpMyAdmin 5.1.1 | Unsupported legacy image |

PHP 7 is end of life and excluded from this image line. The Ubuntu 20.04 PHP 7 and PHP 8 images are unsupported legacy images and receive no fixes or feature work. There are no PHP 7 tags for Ubuntu 22.04, 24.04, or 26.04, and no generic Ubuntu release tags; use an explicit PHP 8.5 tag, which provides PHP 8.5.12.

phpMyAdmin is deliberately omitted because it is not part of the PHP 8.5.12-compatible image stack. The PHP 8.5.12 images bundle the smaller MySQL-only Adminer 6.1.2 asset instead.

> **Migration warning:** do not mount an existing 20.04 MySQL data directory into a newer image. Take a logical backup (for example, `mysqldump`) from the 20.04 container and restore it into a new 22.04, 24.04, or 26.04 MySQL volume.

## Usage

The examples below use the Ubuntu 24.04 image. Replace
`latest-2404-php8.5` with `latest-2204-php8.5` or
`latest-2604-php8.5` when needed. All container processes use UID:GID
`1000:1000`; mount application code read-only and use a new named volume for
MySQL unless an operator has already prepared a writable `1000:1000` host
directory.

### On the command line

1. Create a small application directory:

   ```bash
   mkdir -p app
   printf '<?php phpinfo();\n' > app/index.php
   ```

2. Create a named volume for this image generation's MySQL data:

   ```bash
   docker volume create docker-lamp-mysql-2404
   ```

3. Start the image. The first startup creates the local MySQL `admin` account
   with the password supplied in `MYSQL_ADMIN_PASS`:

   ```bash
   docker run --name docker-lamp --rm -p 80:8080 \
     -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
     -v "${PWD}/app:/app:ro" \
     -v docker-lamp-mysql-2404:/var/lib/mysql \
     mattrayner/lamp:latest-2404-php8.5
   ```

4. Open `http://localhost/`. Apache listens on container port `8080`; the
   host mapping above keeps the familiar port `80` URL. Stop the foreground
   container with `Ctrl-C`, or add `-d` to run it in the background.

MySQL port `3306` is not published by default. Do not add a port mapping just
for local administration: use Adminer or `docker exec`. Publishing MySQL is an
advanced, first-run configuration that also requires an explicit non-loopback
`MYSQL_BIND_ADDRESS`.

### With a Dockerfile

Use a Dockerfile when the application and its dependencies should travel with
the image instead of a bind mount:

```dockerfile
FROM mattrayner/lamp:latest-2404-php8.5

COPY --chown=1000:1000 app/ /app/
```

Build and run it with the same named volume and first-run password:

```bash
docker build -t my-lamp-app .
docker run --name my-lamp-app --rm -p 80:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  my-lamp-app
```

### MySQL databases

#### Adminer

Open `http://localhost/adminer/`. The login page pre-fills `localhost`; sign
in as `admin` with the value supplied in `MYSQL_ADMIN_PASS`. Adminer is a
development convenience, not an authentication boundary: do not publish it to
an untrusted network, and put network controls or authentication in front of
it when necessary.

#### Command line

Create a database from the running container:

```bash
docker exec docker-lamp env MYSQL_PWD='choose-a-strong-password' \
  mysql --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin \
  -e 'CREATE DATABASE my_application'
```

For an application account on a fresh volume, provide all three variables at
first startup: `MYSQL_USER_NAME`, `MYSQL_USER_DB`, and `MYSQL_USER_PASS` (or
the corresponding `*_FILE` password input). Existing ready volumes do not
change accounts or passwords from later environment values.

#### Initialization scripts

Mount trusted initialization files at `/docker-entrypoint-initdb.d:ro` before
the first startup. Files run once, in lexical order: `.sql`, `.sql.gz`, and
executable hook files are supported.

```bash
mkdir -p mysql-init
printf 'CREATE DATABASE my_application;\n' > mysql-init/10-create-database.sql

docker run --name docker-lamp --rm -p 80:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app:ro" \
  -v "${PWD}/mysql-init:/docker-entrypoint-initdb.d:ro" \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  mattrayner/lamp:latest-2404-php8.5
```

Initialization imports are not a migration or recovery mechanism. They never
replay on a ready volume; interrupted or inconsistent initialization fails
closed and should be recovered into a fresh volume from a tested logical
backup.

### Persisting and moving MySQL data

The named-volume example above persists data across container replacement. Do
not copy a live MySQL data directory or mount a legacy Ubuntu 20.04 data
directory into these images. Take a logical backup and restore it into a new
volume instead:

```bash
docker exec docker-lamp env MYSQL_ADMIN_PASS='choose-a-strong-password' \
  docker-lamp-backup --database my_application > my_application.sql

docker exec -i docker-lamp env MYSQL_ADMIN_PASS='choose-a-strong-password' \
  docker-lamp-restore --database my_application < my_application.sql
```

The target database must already exist. Backup and restore accept trusted SQL
only; see the recovery guidance below for their consistency and recovery
limits.

### HTTPS, PHP configuration, and backups

External TLS termination is the recommended production setup: the proxy owns public ports `80`/`443`, certificates, and redirects, then forwards HTTP to container port `8080`. Native TLS is available only when explicitly enabled and maps public `443` to container `8443`:

```bash
docker run --rm -p 80:8080 -p 443:8443 \
  --mount type=bind,src="${PWD}/secrets/mysql-admin-password",dst=/run/secrets/mysql-admin-password,readonly \
  --mount type=bind,src="${PWD}/secrets/tls.crt",dst=/run/secrets/tls.crt,readonly \
  --mount type=bind,src="${PWD}/secrets/tls.key",dst=/run/secrets/tls.key,readonly \
  -e APACHE_TLS_ENABLED=1 \
  -e APACHE_TLS_CERT_FILE=/run/secrets/tls.crt \
  -e APACHE_TLS_KEY_FILE=/run/secrets/tls.key \
  -v "${PWD}/app:/app:ro" \
  mattrayner/lamp:latest-2404-php8.5
```

TLS files must be regular and readable by UID:GID `1000:1000`. This all-in-one image has a shared UID, so PHP can read a key readable by Apache; use external termination or separate services when key isolation is required. Native TLS redirects `8080` to HTTPS and deliberately does not trust `X-Forwarded-*` headers. Do not configure a proxy to terminate TLS at the image unless it has an explicit trusted-proxy boundary outside this image.

Mount additive PHP `.ini` files at `/etc/docker-lamp/php/conf.d:ro`; PHP scans them in filename order after image configuration. Set `PHP_USER_OVERRIDES_DISABLED=1` to bypass only that directory for recovery. Xdebug is disabled by default for Apache, CLI, Composer, and `docker exec php`; opt in for all of them with `XDEBUG_ENABLED=1`. Use its standard `XDEBUG_MODE` and `XDEBUG_CONFIG` environment variables (for example, `XDEBUG_MODE=debug` and `XDEBUG_CONFIG='client_host=host.docker.internal client_port=9003'`) for connection settings.

`docker-lamp-backup --database NAME` writes a dump of exactly one existing database to stdout and diagnostics to stderr. `docker-lamp-restore --database NAME [--input FILE]` reads trusted SQL from stdin or a file and executes it as the MySQL `admin` user; it is not database-confined or transactional. A restore can therefore overwrite data beyond the named target and can leave partial changes when SQL fails. Use it only with trusted SQL and a tested backup. The command requires the named target to already exist, but never creates, drops, clears, or replays initialization imports itself. Supply `MYSQL_ADMIN_PASS` or `MYSQL_ADMIN_PASS_FILE` for either command. Logical dumps also have normal concurrent-DDL/non-transactional-table consistency limits; copying a live data directory is unsupported.

### Kubernetes and recovery

For the Restricted-style Kubernetes manifest, PVC/CSI/NFS and Secret-projection limitations, storage paths, isolation boundaries, and the fixed-identity migration/recovery lifecycle, see the [Kubernetes, storage, and recovery guide](docs/kubernetes.md). The all-in-one image uses one shared UID for PHP and MySQL; use a separate deployment architecture when service or Secret isolation is required.

## Development

The final images consume release-specific, prebuilt PHP artifacts rather than
installing PHP during their own builds. The artifact is a separate image for
each Ubuntu release and must use a fixed tag; floating PHP artifact tags are
not supported.

Local testing requires Docker Buildx and a `DOCKER_DEFAULT_PLATFORM` matching
the image architecture you want to test (for example, `linux/amd64` or
`linux/arm64`). The test runner builds the three local artifact images from
`php-builder/Dockerfile` before it builds the Compose services:

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
./tests/test.sh
docker compose -f docker-compose.test.yml -p ci down --volumes --remove-orphans
```

The test Compose file builds and runs all three images concurrently with ephemeral loopback HTTP ports. Docker Compose v2 is preferred; the test runner falls back to `docker-compose` when it is the only available command.

```bash
./tests/test.sh
docker compose -f docker-compose.test.yml -p ci down --volumes --remove-orphans
```

`tests/test.sh` starts from a fresh `ci` test project, then runs the same behavioral suite against every Ubuntu variant. It uses bounded waits for Apache, Supervisor, and MySQL, prints redacted Compose logs on timeout or failure, and checks behavior and versions rather than a full HTML package snapshot. The suite also verifies the `/adminer/` login form and a credentialed local Adminer session without printing credentials.

CI can test one already-pushed candidate without rebuilding it by setting
`TEST_VARIANTS` to its Ubuntu variant, `TEST_IMAGE` to its immutable final
image reference (for example `repository/lamp@sha256:...`), and
`TEST_PHP_ARTIFACT_IMAGE` to its immutable PHP artifact reference. Set both
`PREBUILT_FINAL_IMAGES=1` and `PREBUILT_PHP_ARTIFACTS=1`; this makes the test
runner pull only the selected final service and use `--no-build`. These inputs
are for candidate CI and do not change the default local workflow above.

Run the slower rootless runtime/remediation suite explicitly when changing container startup, permissions, or process supervision:

```bash
RUN_ROOTLESS_RUNTIME_TESTS=1 ./tests/test.sh
```

## Building and releasing

When releases are approved, build and test all variants before publishing their explicit tags. PHP artifact manifests are release-qualified and immutable: `8.5.12-ubuntu<version>-r1-<release-tag>`. Publish them first, then build each final image with its corresponding immutable `PHP_ARTIFACT_IMAGE` build argument:

```bash
./tests/test.sh

RELEASE_TAG=v1.2.3
docker buildx build --platform linux/amd64,linux/arm64 --target artifact \
  --build-arg UBUNTU_VERSION=22.04 --build-arg PHP_VERSION=8.5.12 \
  -f php-builder/Dockerfile -t mattrayner/lamp-php:8.5.12-ubuntu22.04-r1-${RELEASE_TAG} --push .

docker build --build-arg PHP_ARTIFACT_IMAGE=mattrayner/lamp-php:8.5.12-ubuntu22.04-r1-${RELEASE_TAG} \
  -f 2204/Dockerfile -t mattrayner/lamp:latest-2204-php8.5 .
```

Do not create PHP 7 or generic Ubuntu release tags. Keep `latest` policy separate from these explicit PHP 8.5 release tags.

## License

Docker-LAMP is licensed under the [Apache 2.0 License](LICENSE).
