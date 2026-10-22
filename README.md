# Docker-LAMP

Docker-LAMP packages Apache, MySQL, and PHP in one development image. The current image line provides PHP 8.5 and MySQL 9.7 LTS on Ubuntu 22.04, 24.04, and 26.04.

## Image versions

| Image | Ubuntu | PHP | MySQL | Database UI | Support |
| --- | --- | --- | --- | --- | --- |
| `latest-2204-php8.5` (planned release) | 22.04 LTS | 8.5 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2404-php8.5` (planned release) | 24.04 LTS | 8.5 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2604-php8.5` (planned release) | 26.04 LTS | 8.5 | 9.7 LTS | Adminer 6.1.2 at `/adminer/` | Current |
| `latest-2004-php8` | 20.04 LTS | 8.0 | 8.0 | phpMyAdmin 5.1.1 | Unsupported legacy image |
| `latest-2004-php7` | 20.04 LTS | 7.4 | 8.0 | phpMyAdmin 5.1.1 | Unsupported legacy image |

PHP 7 is end of life and excluded from this image line. The Ubuntu 20.04 PHP 7 and PHP 8 images are unsupported legacy images and receive no fixes or feature work. There are no PHP 7 tags for Ubuntu 22.04, 24.04, or 26.04, and no generic Ubuntu release tags; use an explicit PHP 8.5 tag.

phpMyAdmin is deliberately omitted because it is not part of the PHP 8.5-compatible image stack. The PHP 8.5 images bundle the smaller MySQL-only Adminer 6.1.2 asset instead.

> **Migration warning:** do not mount an existing 20.04 MySQL data directory into a newer image. Take a logical backup (for example, `mysqldump`) from the 20.04 container and restore it into a new 22.04, 24.04, or 26.04 MySQL volume.

## Usage

Choose the Ubuntu base appropriate for your application and mount its source at `/app`:

```bash
docker run --rm -p 8080:80 -p 3306:3306 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app" \
  mattrayner/lamp:latest-2404-php8.5
```

Replace `latest-2404-php8.5` with `latest-2204-php8.5` or `latest-2604-php8.5` as required. The first startup creates the `admin` MySQL user using `MYSQL_ADMIN_PASS`. It is available over TCP on port 3306; do not expose that port on an untrusted network. The local MySQL `root` account is intended only for in-container administration.

### Adminer for beginners

Open `http://localhost:8080/adminer/` after starting the container. The login page pre-fills the server as `localhost`; sign in with username `admin` and the value supplied in `MYSQL_ADMIN_PASS`. Adminer does not store or bypass credentials, and the image verifies the bundled Adminer 6.1.2 MySQL-only file by SHA-256 during its build.

Adminer is a powerful database administration tool. Treat `/adminer/` as a development convenience: do not publish it to an untrusted network, use a strong `MYSQL_ADMIN_PASS`, and place authentication or network controls in front of it if it must be reachable outside a local development machine.

To persist a database, use a new named volume for the selected variant:

```bash
docker volume create docker-lamp-mysql-2404
docker run --rm -p 8080:80 -p 3306:3306 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app" \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  mattrayner/lamp:latest-2404-php8.5
```

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

The test Compose file builds and runs all three images concurrently on non-conflicting ports: 3020/3021 for 22.04, 3040/3041 for 24.04, and 3060/3061 for 26.04 (HTTP/MySQL respectively). Docker Compose v2 is preferred; the test runner falls back to `docker-compose` when it is the only available command.

```bash
./tests/test.sh
docker compose -f docker-compose.test.yml -p ci down --volumes --remove-orphans
```

`tests/test.sh` starts from a fresh `ci` test project, then runs the same behavioral suite against every Ubuntu variant. It uses bounded waits for Apache, Supervisor, and MySQL, prints redacted Compose logs on timeout or failure, and checks behavior and versions rather than a full HTML package snapshot. The suite also verifies the `/adminer/` login form and a credentialed local Adminer session without printing credentials.

## Building and releasing

When the releases are approved, build and test all variants before publishing their explicit tags. Publish the versioned multi-architecture PHP artifacts first, then build each final image with its corresponding immutable `PHP_ARTIFACT_IMAGE` build argument:

```bash
./tests/test.sh

docker buildx build --platform linux/amd64,linux/arm64 --target artifact \
  --build-arg UBUNTU_VERSION=22.04 --build-arg PHP_VERSION=8.5.12 \
  -f php-builder/Dockerfile -t mattrayner/lamp-php:8.5.12-ubuntu22.04-r1 --push .

docker build --build-arg PHP_ARTIFACT_IMAGE=mattrayner/lamp-php:8.5.12-ubuntu22.04-r1 \
  -f 2204/Dockerfile -t mattrayner/lamp:latest-2204-php8.5 .
```

Do not create PHP 7 or generic Ubuntu release tags. Keep `latest` policy separate from these explicit PHP 8.5 release tags.

## License

Docker-LAMP is licensed under the [Apache 2.0 License](LICENSE).
