# 1.0.0

## Images and runtime

- Provide PHP 8.5.12 and MySQL 9.7 LTS images for Ubuntu 22.04, 24.04, and 26.04 on amd64 and arm64, using official Ubuntu base images.
- Run Apache, PHP, MySQL, and Supervisor as UID:GID `1000:1000`, including startup. No root bootstrap, runtime UID/GID remapping, or automatic host ownership changes.
- Support a read-only root filesystem with writable runtime and data mounts, dropped capabilities, and no privilege escalation.
- Add signal forwarding, bounded service shutdown, and a watchdog that stops the container when a critical service fails.
- Bundle Composer and checksum-verified Adminer 6.1.2 at `/adminer/` instead of phpMyAdmin.

## MySQL

- Require an explicit first-run admin password through `MYSQL_ADMIN_PASS` or `MYSQL_ADMIN_PASS_FILE`. Lock the bootstrap root account and support a separate application user and database through `MYSQL_USER_*` settings.
- Track database initialization with `initializing` and `ready` states. Refuse startup after interrupted or inconsistent initialization; preserve existing credentials and skip imports on initialized volumes.
- Run trusted `.sql`, `.sql.gz`, and executable initialization files from `/docker-entrypoint-initdb.d` once, in filename order. Validate inputs before initialization and handle interruptions during imports.
- Bind MySQL to `127.0.0.1` by default, with explicit listener configuration through `MYSQL_BIND_ADDRESS`.
- Add `docker-lamp-backup` and `docker-lamp-restore` for single-database logical backups and restores using temporary credential files. Restore requires an existing target database and trusted SQL; it is not transactional or confined to that database.

## Apache and PHP

- Serve HTTP on container port `8080`. Add optional native TLS on `8443`, certificate/key validation, and redirects to public HTTPS port `443` without trusting forwarded headers.
- Validate `APACHE_ROOT` and keep test-only Apache configuration out of the images.
- Load additional PHP configuration from `/etc/docker-lamp/php/conf.d` in filename order. Allow that directory to be bypassed with `PHP_USER_OVERRIDES_DISABLED=1`.
- Disable Xdebug by default. Enable it for Apache, CLI, Composer, and `docker exec php` with `XDEBUG_ENABLED=1`.

## Documentation and testing

- Rewrite the usage guide with step-by-step setup, non-root operation, bind-mount permissions, database administration, TLS, and backup instructions.
- Add [application examples](examples/README.md) for WordPress, Concrete CMS (concrete5), and a PHP application with writable uploads and cache directories. Explain host-side editing, targeted ACLs, compatibility requirements, and CMS update limitations.
- Document Docker Desktop setup on macOS and Windows/WSL2, including host file sharing, Linux versus Windows filesystem permissions, and writable-mount checks. Desktop-specific behavior is not covered by the Linux CI matrix.
- Add a Kubernetes deployment template and [storage and recovery guide](docs/kubernetes.md), including a Restricted security context, writable mounts, single-writer deployment strategy, and storage-driver limitations.
- Expand integration coverage for permissions, persistence, service failures, shutdown, MySQL initialization and credential handling, TLS, PHP configuration, Xdebug, and backup/restore.
- Test all three Ubuntu variants on native amd64 and arm64 runners, plus live Restricted-policy Kubernetes validation. Make test fixtures work when the host UID differs from the container UID.
- Build PHP artifacts separately for each Ubuntu version and test published release candidates by digest before promoting multi-architecture release tags.

## Upgrading

- Use the explicit `latest-2204-php8.5`, `latest-2404-php8.5`, or `latest-2604-php8.5` tags. Ubuntu 20.04 PHP 7/8 images remain unsupported; their test coverage is removed from this image line.
- Change HTTP port mappings from container port `80` to `8080`. Native HTTPS requires an explicit `443:8443` mapping and TLS configuration. MySQL is not published by default.
- Replace passwordless-root or generated-password workflows with explicit credentials. Use `/docker-entrypoint-initdb.d` instead of the legacy `/db/init.sql` mount for first-run imports.
- Export databases from legacy images with `mysqldump` and restore into a fresh volume. Do not reuse an older MySQL data directory or remove initialization markers to force startup.
- Keep application source read-only and prepare writable host directories for the container user. PHP and MySQL share the same UID and can access the same readable secrets; use separate services when isolation is required.

Historical dates below are the GitHub release publication dates in UTC.
Entries summarize the linked release notes, except where a commit comparison
is explicitly cited.

# 0.9.0 - 2024-03-26

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.9.0)

- Add support for a MySQL initialization script ([#128](https://github.com/mattrayner/docker-lamp/pull/128)).
- Fix `.htaccess` handling under `/var/www/html` ([#138](https://github.com/mattrayner/docker-lamp/pull/138)).

# 0.8.0 - 2021-09-21

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.8.0)

- Add Ubuntu 20.04 images and PHP 8 variants.
- Drop support for Ubuntu 16.04 because its dependencies no longer allow reliable builds.

# 0.7.0 - 2020-06-08

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.7.0)

- Fix startup-script errors affecting the Ubuntu 18.04 image ([#89](https://github.com/mattrayner/docker-lamp/issues/89)).
- Update phpMyAdmin to 5.0.2 and apply minor PHP and MySQL updates.

# 0.6.0 - 2020-03-15

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.6.0)

- Fix image-build and startup-script issues that prevented PHP version updates.
- Update PHP to 7.4 and phpMyAdmin to 5.0.1.
- Add regression coverage for [#63](https://github.com/mattrayner/docker-lamp/issues/63).

# 0.5.0 - 2019-06-12

[GitHub release](https://github.com/mattrayner/docker-lamp/releases/tag/0.5.0)

This release has no published notes. The following summary is based on the
[commits between 0.4.0 and 0.5.0](https://github.com/mattrayner/docker-lamp/compare/0.4.0...0.5.0):

- Add Ubuntu 18.04 support and update the image tests.
- Remove PHP 5 support and official Ubuntu 14.04 support.
- Correct the Phusion base-image versions for Ubuntu 16.04 and 18.04.
- Set MySQL's bind address to `0.0.0.0`.
- Migrate builds to CircleCI 2.0 and update release tagging.

# 0.4.0 - 2018-08-22

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.4.0)

- Add PHP 7 image variants, along with contributed features and fixes.

# 0.3.0 - 2016-10-17

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.3.0)

- Change CLI PHP to version 5.6.
- Add Composer.
- Set the timezone to `Europe/London`.

# 0.2.1 - 2016-08-23

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.2.1)

- Expand documentation for the main image usage scenarios.
- Run tests in a container rather than relying on tools installed on the host.

# 0.2.0 - 2016-08-22

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.2.0)

- Provide both Ubuntu 14.04 and Ubuntu 16.04 base-image variants.

# 0.2.0-alpha - 2016-08-21 (pre-release)

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.2.0-alpha)

- Publish the Phusion baseimage-based alpha. The original changelog records the move to an updated base image and Ubuntu 16.04.

# 0.1.1 - 2016-08-20 (pre-release)

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.1.1)

- Update OS packages to address high-severity vulnerabilities reported by Quay.io.

# 0.1.0 - 2016-08-20 (pre-release)

[Release notes](https://github.com/mattrayner/docker-lamp/releases/tag/0.1.0)

- Initial development release. The original changelog notes compatibility with Concrete5.
