# Docker-LAMP

Docker-LAMP runs Apache, MySQL, and PHP together in one container. You keep
your application files on your computer and share that folder with the
container at `/app`. Docker manages a separate storage area for your database.

The images use PHP 8.5.12 and MySQL 9.7 LTS, with a choice of Ubuntu
22.04, 24.04, or 26.04. Each image supports Intel/AMD processors (`amd64`)
and ARM processors (`arm64`, including Apple silicon). It includes
[Composer](https://getcomposer.org/) for PHP dependencies and
[Adminer](https://www.adminer.org/) for managing databases in your browser.

## Contents

- [Image versions](#image-versions)
- [Using the image](#using-the-image)
  - [Running without root](#running-without-root)
  - [macOS and Windows](#macos-and-windows)
- [Application examples](examples/README.md)
- [MySQL databases](#mysql-databases)
- [PHP configuration](#php-configuration)
- [HTTPS](#https)
- [Kubernetes](#kubernetes)
- [Development](#development)
- [Building and releasing](#building-and-releasing)

## Image versions

The tags below are not yet published. To build and test locally, follow
the [development instructions](#development).

| Tag | Ubuntu | PHP | MySQL |
| --- | --- | --- | --- |
| `mattrayner/lamp:latest-2204-php8.5` | 22.04 LTS | 8.5.12 | 9.7 LTS |
| `mattrayner/lamp:latest-2404-php8.5` | 24.04 LTS | 8.5.12 | 9.7 LTS |
| `mattrayner/lamp:latest-2604-php8.5` | 26.04 LTS | 8.5.12 | 9.7 LTS |

Use the full PHP 8.5 tag rather than `latest` or a generic Ubuntu tag.
PHP 8.5.12 is the minimum supported version. Images for other PHP generations
are unsupported, even if their tags are still available on Docker Hub.

Adminer 6.1.2 is included for database administration at `/adminer/`.

## Using the image

The examples use Ubuntu 24.04. You can substitute either of the other tags
without changing the commands. Run them from your project directory, with
Docker installed and running. If you haven't installed Docker yet, follow
the [Docker installation guide](https://docs.docker.com/get-started/get-docker/)
and the platform notes below. Installing Docker or WSL may require
administrator permission; that is separate from running this image.

### Running without root

The container uses an ordinary Linux account, not the administrator account
(called **root**). Apache, PHP, MySQL, and Supervisor all use that account,
including during startup. Its user ID (UID) and group ID (GID) are both
`1000`, written as `1000:1000` in Docker commands.

You don't need `sudo` inside the container or the `--privileged` option.
Don't change the account with `--user`; the image expects `1000:1000`.

The quick start keeps MySQL in a [Docker volume](https://docs.docker.com/engine/storage/volumes/):
a storage area managed by Docker, separate from your application folder.
A fresh volume gets the permissions it needs automatically, so you don't
need to change its owner with `chown`. Your account on your own computer
doesn't need to be UID 1000; the container just needs permission to read your
application files. Shared folders for uploads or other writable data also
need permission to write.
See [adding your own content](#adding-your-own-content).

Docker access on your machine is separate. These commands assume you can
already run `docker info` without sudo. Docker Desktop handles this as part
of its setup. On Linux, see [Docker's rootless mode](https://docs.docker.com/engine/security/rootless/)
to run Docker itself without root. The alternative of joining the `docker`
group gives effectively administrator-level access to your computer; see
[Docker's Linux setup notes](https://docs.docker.com/engine/install/linux-postinstall/)
before choosing that approach.

The quick start uses port `8080` on both your computer and the container.
The [HTTPS example](#https) uses ports `80` and `443` on your computer;
opening these lower-numbered ports may need extra setup with rootless Docker,
even though Apache uses higher-numbered ports inside the container.

### macOS and Windows

These images run Linux software. Docker Desktop provides the Linux
environment on macOS and Windows.

- **macOS:** install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/),
  then run the examples in Terminal. Keep your project in a folder Docker
  Desktop can share, such as a folder under your home directory.
- **Windows:** install [WSL 2 (Windows Subsystem for Linux)](https://learn.microsoft.com/en-us/windows/wsl/install)
  and [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/).
  WSL lets you run Linux tools on Windows. Follow
  [Docker's WSL setup guide](https://docs.docker.com/desktop/features/wsl/) to
  connect Docker to your installed Linux system, such as Ubuntu. Open Ubuntu
  from the Start menu and run this guide's examples in its terminal, not in
  PowerShell or Command Prompt.

On Windows, keep the project in your Linux home folder, such as
`~/projects/my-app` (`~` means your home folder). Avoid `/mnt/c`, which is
your Windows C: drive as seen from Linux. You can edit Linux files from the
Windows desktop with [Visual Studio Code's WSL extension](https://code.visualstudio.com/docs/remote/wsl).

You don't need to change the container user to match a macOS or Windows
account. Docker Desktop handles sharing files with the container, but your
folders must still allow the access your application needs. Keep MySQL in a
Docker-managed volume rather than a folder shared from macOS or Windows.

See the [platform permission notes](examples/README.md#macos-and-windows)
and run the small write test there before using uploads or cache folders.
Don't copy Linux ownership or permission commands onto macOS or Windows
without checking which filesystem they apply to.

### On the command line

1. Put your PHP files in an `app` directory (folder). To try the image in
   an empty project, create a simple page:

   ```bash
   mkdir -p app
   printf '%s\n' '<?php echo "Hello from Docker-LAMP";' > app/index.php
   ```

2. Create a volume for MySQL. This keeps your databases when you replace the
   container:

   ```bash
   docker volume create docker-lamp-mysql-2404
   ```

3. Start the container. Replace the example password with your own:

   ```bash
   docker run --detach --name docker-lamp --stop-timeout 75 \
     -p 127.0.0.1:8080:8080 \
     -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
     -v "${PWD}/app:/app:ro" \
     -v docker-lamp-mysql-2404:/var/lib/mysql \
     mattrayner/lamp:latest-2404-php8.5
   ```

4. Give MySQL time to finish its first startup, then open
   [http://localhost:8080/](http://localhost:8080/). If the page isn't ready,
   check the startup log:

   ```bash
   docker logs docker-lamp
   ```

This publishes the site only on your own machine. Apache uses port `8080`
inside the container; to use a different host port, change the middle number
in `127.0.0.1:8080:8080`.

Stop and start it again with:

```bash
docker stop docker-lamp
docker start docker-lamp
```

Your database stays in the named volume. `docker rm docker-lamp` removes a
stopped container, not that volume. Don't delete the volume unless you also
intend to delete its databases.

### Adding your own content

The `app` mount is a [bind mount](https://docs.docker.com/engine/storage/bind-mounts/):
your local directory appears at `/app` inside the container. It isn't a copy
of your code. Edit the files with your
usual editor and refresh the browser to see the changes, subject to any
application caching. You don't need to rebuild the image.

The `:ro` option makes the mount read-only **inside the container**. It does
not stop you editing the files on your machine or change their ownership.
The mount also hides the image's built-in `/app` files; their ownership does
not override the permissions on your source directory.

On a standard Linux Docker installation, the usual directory permissions
(`0755`) let other users open folders, and the usual file permissions (`0644`)
let them read files. That includes the container user, even if your own UID
isn't 1000. Owner-only permissions (`0700` for folders or `0600` for files)
block access by a different user. Grant access only where needed, especially
for files containing passwords. Docker Desktop and rootless Docker may
translate user IDs differently, so test access before changing ownership.

If your application serves from a `public` directory, add
`-e APACHE_ROOT=/app/public` before the image name in `docker run`.

PHP runs as `1000:1000`. If your app needs to save uploads or cache files,
give those directories their own writable mounts while leaving the source
read-only. The image won't repair their permissions at startup. Unlike the
MySQL volume, a bind-mounted directory keeps the host's permissions.

The [application examples](examples/README.md) show this setup for
[WordPress](examples/README.md#wordpress),
[Concrete CMS (concrete5)](examples/README.md#concrete-cms-concrete5), and a
[PHP app with uploads and a cache](examples/README.md#a-php-app-with-uploads-and-a-cache).
They also cover checking permissions and the difference between editing code
on your machine and installing extensions through a CMS dashboard.

### With a Dockerfile

To package your code with the image rather than mount it, put this Dockerfile
beside your `app` directory:

```dockerfile
FROM mattrayner/lamp:latest-2404-php8.5

COPY --chown=0:0 app/ /app/
```

Keep the copied files readable by the runtime user, but not writable by its
group or by everyone. The base image already supplies the startup command
and non-root user.

Build it, then stop the quick-start container before reusing its database
volume:

```bash
docker build -t my-lamp-app .
docker stop docker-lamp
docker run --detach --name my-lamp-app --stop-timeout 75 \
  -p 127.0.0.1:8080:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  my-lamp-app
```

This is an alternative to the quick start, not a second server for the same
data. Never run two containers against the same MySQL volume. The examples
below use the quick-start container name, `docker-lamp`; substitute yours if
you chose a different name.

## MySQL databases

On an empty volume, the image creates an `admin` account using
`MYSQL_ADMIN_PASS`. There is no passwordless root login and no generated
password to retrieve from the logs. Changing the environment later does
not change accounts or passwords in an existing database.

For a password stored in a mounted file, set `MYSQL_ADMIN_PASS_FILE` instead
of `MYSQL_ADMIN_PASS`. The file must contain one non-empty line and be
readable by `1000:1000`. Use one setting or the other, not both, and keep
password files out of version control.

### Adminer

Open [http://localhost:8080/adminer/](http://localhost:8080/adminer/).
Leave the server as `localhost` and log in as `admin` with the password you
chose. You can create databases and run SQL from there.

Adminer gives access to your databases. Keep it private; if you publish the
site beyond your machine, restrict access to `/adminer/` through your proxy
or network rules.

### Creating a database from the command line

This asks for your admin password, then creates `my_application`:

```bash
docker exec -it docker-lamp mysql \
  --protocol=socket --socket=/run/mysql/mysqld.sock -uadmin -p \
  -e 'CREATE DATABASE my_application'
```

You can also create a database and a separate application account at first
startup. Set `MYSQL_USER_NAME`, `MYSQL_USER_DB`, and `MYSQL_USER_PASS`
together when starting with an empty volume. `MYSQL_USER_PASS_FILE` can
replace the password value. Use this account in your app rather than `admin`.

MySQL listens on `127.0.0.1` inside the container by default. PHP and Adminer
can connect without publishing port `3306`. To allow an external database
client, you also need a non-loopback `MYSQL_BIND_ADDRESS` and an account
permitted to connect remotely; publishing the port alone isn't enough. See
the [storage and recovery guide](docs/kubernetes.md) before changing this.

### Initialization scripts

To set up a database, you can supply SQL files in
`/docker-entrypoint-initdb.d`. They run once, in filename order, before the
web server starts. The directory can contain `.sql`, `.sql.gz`, and readable
executable scripts. Only mount files you trust.

This example uses a separate, empty volume. If you have already followed the
quick start, stop that container first to free port `8080`:

```bash
docker stop docker-lamp
mkdir -p mysql-init
printf 'CREATE DATABASE my_application;\n' > mysql-init/10-create-database.sql
docker volume create docker-lamp-mysql-init-2404

docker run --detach --name docker-lamp-init --stop-timeout 75 \
  -p 127.0.0.1:8080:8080 \
  -e MYSQL_ADMIN_PASS='choose-a-strong-password' \
  -v "${PWD}/app:/app:ro" \
  -v "${PWD}/mysql-init:/docker-entrypoint-initdb.d:ro" \
  -v docker-lamp-mysql-init-2404:/var/lib/mysql \
  mattrayner/lamp:latest-2404-php8.5
```

Reusing a volume that already contains a database will not rerun these files.
If initialization is interrupted, the image refuses to start that database
again. Follow the [recovery guide](docs/kubernetes.md#migration-and-recovery-lifecycle)
rather than deleting its state marker or trying to replay the imports.

### Backups and restores

For the database created above, replace `CONTAINER` with `docker-lamp` or
`docker-lamp-init`, as appropriate:

```bash
docker exec CONTAINER docker-lamp-backup --database my_application > my_application.sql
docker exec -i CONTAINER docker-lamp-restore --database my_application < my_application.sql
```

The tools use the admin password or password-file setting supplied when the
container was created. The backup goes to stdout and diagnostics go to
stderr. Restore reads stdin, or you can use `--input /path/inside/container.sql`.

To move a database, back it up from the source container, start the destination
container with an empty volume, create the target database, then restore into
it. If the source image doesn't include these helpers, use `mysqldump`.
When changing MySQL versions, transfer data this way rather than attaching
the source data directory to the destination container.

Restore runs SQL as `admin`: it can overwrite data, affect other databases,
and leave partial changes if a statement fails. Only restore trusted dumps.
It requires an existing target database and does not create or empty it for
you. Avoid schema changes during backup, arrange a quiet period for
non-transactional tables, and never back up by copying a live data directory.

## PHP configuration

Put your extra `.ini` files in a local directory and mount it at
`/etc/docker-lamp/php/conf.d:ro`. Files load in filename order after the
image's settings. For example, a file named `99-app.ini` could contain:

```ini
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 20M
```

If an override causes trouble, recreate the container with
`PHP_USER_OVERRIDES_DISABLED=1` to skip that directory without disabling the
image's PHP configuration.

[Xdebug](https://xdebug.org/docs/step_debug) lets you step through PHP code
in your editor. It is off by default. Add `-e XDEBUG_ENABLED=1` to enable it
for Apache, command-line PHP, Composer, and `docker exec php`. Configure it with
`XDEBUG_MODE` and `XDEBUG_CONFIG` variables. For example, use
`XDEBUG_MODE=debug` and
`XDEBUG_CONFIG='client_host=host.docker.internal client_port=9003'`.
On Linux, you may also need
`--add-host=host.docker.internal:host-gateway` so that address reaches your editor.

## HTTPS

For a public site, we recommend handling certificates and redirects in a
reverse proxy and forwarding HTTP to container port `8080`. Leave native
TLS disabled in that setup. The image does not trust `X-Forwarded-*` headers;
configure any proxy-aware application settings separately.

To serve HTTPS directly, prepare a certificate, its matching private key,
and a MySQL password file in a local `secrets` directory. All three files
must be readable by `1000:1000`; don't make the private key world-readable.
Stop any container using the database volume before starting this one:

```bash
docker run --detach --name docker-lamp-tls --stop-timeout 75 \
  -p 127.0.0.1:80:8080 -p 127.0.0.1:443:8443 \
  --mount "type=bind,src=${PWD}/secrets,dst=/run/secrets,readonly" \
  -e MYSQL_ADMIN_PASS_FILE=/run/secrets/mysql-admin-password \
  -e APACHE_TLS_ENABLED=1 \
  -e APACHE_TLS_CERT_FILE=/run/secrets/tls.crt \
  -e APACHE_TLS_KEY_FILE=/run/secrets/tls.key \
  -v "${PWD}/app:/app:ro" \
  -v docker-lamp-mysql-2404:/var/lib/mysql \
  mattrayner/lamp:latest-2404-php8.5
```

Use a certificate valid for the hostname you browse to. With this mapping,
HTTP on host port `80` redirects to HTTPS on host port `443`. Inside the
container, TLS uses `8443`, and is only enabled when requested. For an
existing volume, the password file must contain its existing admin password.

Apache, PHP, and MySQL share one user. PHP can therefore read MySQL data and
any mounted secrets, including the TLS key. If you need to keep those apart,
use separate web and database services and keep TLS keys at the proxy.

## Kubernetes

The [Kubernetes guide](docs/kubernetes.md) explains the supplied deployment
template, storage permissions, Secret mounts, and recovery. The template
runs as `1000:1000` with a read-only root filesystem and no added
capabilities. Check your storage driver's permission handling before using
it; the image does not repair volume ownership.

## Development

You'll need Docker with [Buildx](https://docs.docker.com/build/) to build the
images and [Compose](https://docs.docker.com/compose/) to run the test
containers together. After downloading or cloning this repository, open a
terminal in its directory, choose your processor type, and run the tests:

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64  # Use linux/arm64 on an ARM machine.
export TEST_COMPOSE_PROJECT=docker-lamp-dev
./tests/test.sh
```

The test runner builds PHP first, then builds and tests each Ubuntu image.
It binds HTTP to temporary local ports and starts MySQL with empty test
data. Use a different `TEST_COMPOSE_PROJECT` for concurrent runs; when unset,
the runner generates a unique name. Docker Compose v2 is preferred, with
`docker-compose` supported as a fallback.

Run the full startup, permissions, shutdown, TLS, and database-lifecycle
checks when changing the runtime:

```bash
RUN_ROOTLESS_RUNTIME_TESTS=1 ./tests/test.sh
```

Add `TEST_VARIANTS=2404` to a test command to run just one Ubuntu variant.
When you're finished, remove the test stacks and their disposable data:

```bash
docker compose -f docker-compose.test.yml -p docker-lamp-dev down --volumes --remove-orphans
docker compose -f docker-compose.test.yml -p docker-lamp-dev-rootless down --volumes --remove-orphans
```

CI can test published images without rebuilding them. Set
`PREBUILT_FINAL_IMAGES=1`, `PREBUILT_PHP_ARTIFACTS=1`, and a single
`TEST_VARIANTS` value, then supply `TEST_IMAGE` and `TEST_PHP_ARTIFACT_IMAGE`
as immutable `repository@sha256:...` references.

## Building and releasing

Each Ubuntu image uses its own prebuilt PHP artifact. Don't mix artifacts
from different Ubuntu releases or use a floating artifact tag.

The [release workflow](.github/workflows/publish-release.yml) builds and tests
native amd64 and arm64 candidates before publishing the release tags. For
a manual build, publish the PHP artifact first, then pass its reference to
the final image build. For example, for Ubuntu 22.04 (replace `v1.2.3` with
your release tag):

```bash
RELEASE_TAG=v1.2.3
docker buildx build --platform linux/amd64,linux/arm64 --target artifact \
  --build-arg UBUNTU_VERSION=22.04 --build-arg PHP_VERSION=8.5.12 \
  -f php-builder/Dockerfile -t mattrayner/lamp-php:8.5.12-ubuntu22.04-r1-${RELEASE_TAG} --push .

docker build --build-arg PHP_ARTIFACT_IMAGE=mattrayner/lamp-php:8.5.12-ubuntu22.04-r1-${RELEASE_TAG} \
  -f 2204/Dockerfile -t mattrayner/lamp:latest-2204-php8.5 .
```

Keep release-qualified PHP artifact tags unchanged once published. Test all
variants before publishing final images, and use the explicit PHP 8.5 tags
listed above.

## License

Docker-LAMP is licensed under the [Apache 2.0 License](LICENSE).
