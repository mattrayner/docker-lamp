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

Choose the Ubuntu base appropriate for your application and mount its source at `/app`:

```bash
docker run --rm -p 80:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app:ro" \
  mattrayner/lamp:latest-2404-php8.5
```

Replace `latest-2404-php8.5` with `latest-2204-php8.5` or `latest-2604-php8.5` as required. The first startup creates the `admin` MySQL user using `MYSQL_ADMIN_PASS`. Apache listens on container port `8080`; MySQL remains unpublished unless an operator explicitly maps port `3306` and uses a non-loopback `MYSQL_BIND_ADDRESS`.

### Adminer for beginners

Open `http://localhost:8080/adminer/` after starting the container. The login page pre-fills the server as `localhost`; sign in with username `admin` and the value supplied in `MYSQL_ADMIN_PASS`. Adminer does not store or bypass credentials, and the image verifies the bundled Adminer 6.1.2 MySQL-only file by SHA-256 during its build.

Adminer is a powerful database administration tool. Treat `/adminer/` as a development convenience: do not publish it to an untrusted network, use a strong `MYSQL_ADMIN_PASS`, and place authentication or network controls in front of it if it must be reachable outside a local development machine.

To persist a database, use a new named volume for the selected variant:

```bash
docker volume create docker-lamp-mysql-2404
docker run --rm -p 80:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app:ro" \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  mattrayner/lamp:latest-2404-php8.5
```

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
