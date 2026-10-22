# Running your application

These examples keep code on your computer so you can edit it and view the
changes through Docker. PHP can read your source files but cannot change
them. You give it write access to specific folders for uploads, caches, or
other files the application needs to save.

- [Before you start](#before-you-start)
- [Directory permissions](#directory-permissions)
  - [macOS and Windows](#macos-and-windows)
- [A PHP app with uploads and a cache](#a-php-app-with-uploads-and-a-cache)
- [WordPress](#wordpress)
- [Concrete CMS (concrete5)](#concrete-cms-concrete5)
- [Stopping and backing up](#stopping-and-backing-up)

## Before you start

Follow the [Docker setup notes](../README.md#running-without-root) first.
Run each example from its own project folder, with application files in
`app/`. Choose your image by running this command in the same terminal you
will use for the rest of the example:

```bash
export LAMP_IMAGE=mattrayner/lamp:latest-2404-php8.5
```

See [image versions](../README.md#image-versions) for tag availability. For a
local build, set `LAMP_IMAGE` to that image's tag instead.

The WordPress and Concrete examples assume you have downloaded the application;
Docker-LAMP doesn't install it for you. Check your exact release,
plugins, and themes against **PHP 8.5 and MySQL 9.7** before using an existing
site. The applications' own requirements, linked below, are a starting point;
not every application or extension has been tested with this image.

Replace the example passwords before running the commands. Each example
creates a separate database volume and application account. Those account
settings only apply to an empty volume; changing them later doesn't reset
passwords. Keep the admin password separate from the application's password.

The sites are available only on your own computer (`127.0.0.1`). The examples
don't open a MySQL port to other computers. Apache/PHP and MySQL share the
same Linux account, so read-only source does not stop PHP from accessing
database files or readable passwords. Use separate containers and database
volumes for separate projects.

## Directory permissions

The **host** is your computer; the **container** runs the application.
Your editor keeps writing to the host files normally. `readonly` in a Docker
mount only affects access through that mount inside the container. For
example, these two mounts make the source read-only but allow PHP to save
uploads:

```text
Host directory                 Container path         Access from PHP
./app                          /app                   Read-only
./app/public/uploads           /app/public/uploads     Read/write
```

The second mount is an exception to the first. Create its directory on the
host before starting Docker. The examples use the same host directory at
both paths, so existing files remain visible; mounting a different, empty
directory there would hide them.

### Preparing writable directories

This recipe is for Docker Engine running directly on Linux, without special
settings that translate user IDs between the host and container. If you use
Docker Desktop, start with the [macOS and Windows notes](#macos-and-windows).

- If `id -u` prints `1000`, directories you create will normally already be
  writable by the container user. No ownership change is needed.
- If your UID differs, you can give UID 1000 access using an **access control
  list (ACL)**: extra permission rules for a particular user. The
  [`setfacl` command](https://man7.org/linux/man-pages/man1/setfacl.1.html)
  changes these rules. On files you own, this keeps your ownership and
  doesn't require `sudo`.

For example, **after creating the generic app's directories below**, run:

```bash
for directory in app/public/uploads app/var/cache; do
  setfacl -R -m u:1000:rwX "$directory"
  find "$directory" -type d -exec setfacl \
    -m "d:u:1000:rwx,d:u:$(id -u):rwx" {} +
done
```

Use the corresponding writable directories for WordPress or Concrete.
This grants access to files inside those folders and their subfolders, and
sets rules for files created there later. It doesn't change the rest of your
source. The rules also let your own account edit files created by PHP. An
application that sets stricter permissions can still block that access.
If you don't own existing files, their owner or an administrator will need
to grant access.

If `setfacl` is missing, look for the `acl` package in your Linux system's
package manager. Installing it may require administrator access. The disk
must also support these permission rules. If it doesn't, ask whoever manages
the computer to help set up access. Don't use `chmod 777`, which gives every
user write access, or change ownership of the whole project.

Docker Desktop, [rootless Docker](https://docs.docker.com/engine/security/rootless/),
and [user-namespace remapping](https://docs.docker.com/engine/security/userns-remap/)
can translate user IDs. In those setups, a host user numbered 1000 isn't
necessarily the container user numbered 1000. Check how your Docker
installation handles IDs before using the recipe above.

The container must also be able to read source files and open the folders
that contain them. The usual `0644` file and `0755` folder permissions allow
this on Linux. For files containing passwords, grant access to the specific
user that needs it rather than letting everyone read them.

### macOS and Windows

The container uses Linux user and group IDs `1000:1000`. Your macOS or Windows
account does not need to match. Docker Desktop shares your folders with a
Linux virtual machine (VM), which runs the container. Both the folder's
permissions and Docker's sharing settings affect access. Use the
[write check](#checking-access-before-startup).

#### macOS with Docker Desktop

1. Install and open [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/).
   Use Terminal for the commands in this guide. Docker chooses the image
   for your processor automatically, whether you have an Intel or Apple
   silicon Mac.
2. Keep the project somewhere Docker Desktop can share, such as
   `~/projects/my-app`. If you see `Mounts denied`, check **Settings →
   Resources → File Sharing** and add the project directory if needed.
   This is separate from granting PHP write permission.
3. Make sure you can read the source and edit the data folders in your
   editor. If Docker Desktop cannot access them, check for macOS privacy
   prompts and [file permissions in Finder](https://support.apple.com/guide/mac-help/change-permissions-for-files-folders-or-disks-mchlp1203/mac).
4. Run the write check for each uploads or cache folder. Don't change the
   container user to match your Mac account or change the owner of your
   whole project to UID 1000.

If your editor can save files but the container cannot, check the folder's
permissions and Desktop's sharing settings. Don't give everyone write
access to the project as a workaround. The Linux `setfacl` commands above
are not instructions for changing permissions on a Mac.

Use a [Docker volume](https://docs.docker.com/engine/storage/volumes/) for
MySQL, as in the examples. Docker manages this storage inside its Linux VM
rather than in your project folder. Volumes can also be faster for caches
that you don't need to edit yourself. However, only the MySQL storage path
has permissions prepared by this image: a volume for an application cache
still needs its own setup. Don't replace a cache folder with an empty volume
and assume PHP will be able to write to it.

See Docker's [Mac permission requirements](https://docs.docker.com/desktop/setup/install/mac-permission-requirements/)
and [file-sharing settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/#file-sharing).

#### Windows with Docker Desktop and WSL2

WSL means **Windows Subsystem for Linux**. It lets you use Linux tools while
working on Windows, without replacing Windows.

1. Follow [Microsoft's WSL installation guide](https://learn.microsoft.com/en-us/windows/wsl/install)
   to install WSL 2 and a Linux system such as Ubuntu. This setup may ask
   you to use PowerShell as an administrator and restart your computer.
2. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
   and follow [Docker's WSL setup guide](https://docs.docker.com/desktop/features/wsl/).
   Enable **Use WSL 2 based engine**, then select Ubuntu (or the Linux system
   you installed) under **Settings → Resources → WSL Integration**. Use
   Linux containers, not Windows containers.
3. Open Ubuntu from the Windows Start menu. Run this guide's application
   commands in that Linux terminal, not in PowerShell or Command Prompt.
   Create your project under your Linux home folder (`~`):

   ```bash
   mkdir -p ~/projects/my-app
   cd ~/projects/my-app
   ```

4. Edit those files from Windows with a tool that supports WSL. For example,
   install [Visual Studio Code](https://code.visualstudio.com/), then follow
   its [WSL extension setup](https://code.visualstudio.com/docs/remote/wsl).
   Once configured, run `code .` from the project folder in Ubuntu to open
   it in your Windows editor while keeping the files in Linux.
5. Run the write check for each data folder. Files in the Linux home folder
   use Linux permissions. The earlier ACL recipe may help if your user ID
   differs, but first check that Docker is not translating those IDs.

In WSL, `/mnt/c` is the Windows C: drive. Keep your project in the Linux
home folder instead: Docker recommends this for speed and for notifying
applications when files change. Files on C: still depend on Windows access
rules, even when opened from Linux. Running `chmod`, `chown`, or `setfacl`
there cannot simply bypass a Windows permission or read-only restriction.
If you must keep the project on C:, check the Windows folder permissions
and test every writable mount.

If you write shell scripts for database initialization, save them with
Linux line endings (`LF`, not Windows `CRLF`) and mark them executable inside
WSL. Your editor's status bar usually has a line-ending selector. Windows
line endings can stop a script from running even when permissions are correct.

See Docker's [WSL setup](https://docs.docker.com/desktop/features/wsl/),
[bind-mount recommendations](https://docs.docker.com/desktop/features/wsl/best-practices/),
and Microsoft's [WSL file-permission explanation](https://learn.microsoft.com/en-us/windows/wsl/file-permissions).

The mount examples have passed basic checks on Linux. These macOS and Windows
notes follow the official guides, but the project's automated Linux tests
do not test Docker Desktop on those systems.

### Checking access before startup

After creating a data folder, run this small test to check that the container
can write to it. It uses the image's normal account, creates a temporary file,
then deletes that file. It does not start Apache or MySQL:

```bash
docker run --rm --entrypoint sh \
  --mount "type=bind,src=${PWD}/app/public/uploads,dst=/write-check" \
  "$LAMP_IMAGE" -ec '
    id
    probe=$(mktemp /write-check/.lamp-permission-check.XXXXXX)
    rm "$probe"
  '
```

Replace `app/public/uploads` with each writable folder from your chosen
example, including the cache. A successful check prints the account details
and finishes without an error. If it says `Permission denied`, fix access to
that folder before starting the application. Making a Docker mount writable
doesn't change the folder's own permissions.

## A PHP app with uploads and a cache

This layout keeps the cache outside the web root:

```text
my-project/
└── app/
    ├── public/
    │   ├── index.php
    │   └── uploads/
    └── var/
        └── cache/
```

1. Create the directories. In an empty project, add a simple test page; skip
   the `printf` command if you already have an `index.php`:

   ```bash
   mkdir -p app/public/uploads app/var/cache
   printf '%s\n' '<?php echo "Hello from my app";' > app/public/index.php
   ```

2. Check the [directory permissions](#directory-permissions) for uploads and
   cache, then start the container:

   ```bash
   docker volume create lamp-generic-mysql
   docker run --detach --name lamp-generic --stop-timeout 75 \
     -p 127.0.0.1:8080:8080 \
     -e APACHE_ROOT=/app/public \
     -e MYSQL_ADMIN_PASS='replace-admin-password' \
     -e MYSQL_USER_NAME=app -e MYSQL_USER_DB=app \
     -e MYSQL_USER_PASS='replace-app-password' \
     --mount "type=bind,src=${PWD}/app,dst=/app,readonly" \
     --mount "type=bind,src=${PWD}/app/public/uploads,dst=/app/public/uploads" \
     --mount "type=bind,src=${PWD}/app/var/cache,dst=/app/var/cache" \
     --mount type=volume,src=lamp-generic-mysql,dst=/var/lib/mysql \
     "$LAMP_IMAGE"
   ```

3. Open `http://localhost:8080/` after initialization. Edit
   `app/public/index.php` on your machine and refresh the page; you do not
   need to rebuild or restart the container.

4. Configure your application to use `/app/public/uploads` for uploads and
   `/app/var/cache` for its cache. These are example paths, not settings that
   Docker-LAMP automatically applies to your framework. Use database `app`,
   user `app`, your application password, and host `localhost`. PHP's MySQL
   socket is configured as `/run/mysql/mysqld.sock`.

You can check the mount boundaries once the container is running:

```bash
docker exec lamp-generic sh -ec '
  test -r /app/public/index.php
  test ! -w /app/public/index.php
  test -w /app/public/uploads
  test -w /app/var/cache
'
```

Upload validation is still your application's responsibility. A writable
uploads directory does not prevent execution of uploaded PHP. For a public
site, reject executable uploads and configure Apache to prohibit their
execution, or store uploads outside the web root and serve them through the
application. Cache and other private runtime data should stay outside `public/`.

## WordPress

The [WordPress PHP compatibility table](https://make.wordpress.org/core/handbook/references/php-compatibility-and-wordpress-versions/)
lists PHP 8.5 support from WordPress 6.9. Choose a maintained release that
supports it, and check your themes and plugins too. See the
[WordPress requirements](https://wordpress.org/about/requirements/) for
database and server requirements.

1. [Download WordPress](https://wordpress.org/download/) and extract it into
   `app/`. `app/index.php`, `app/wp-admin/`, and
   `app/wp-content/` should exist. Prepare the upload directory and copy the
   sample configuration if this is an unconfigured installation:

   ```bash
   mkdir -p app/wp-content/uploads
   cp app/wp-config-sample.php app/wp-config.php
   ```

   Don't overwrite an existing `wp-config.php`. Prepare and check permissions
   for `app/wp-content/uploads` using the steps above.

2. Edit `app/wp-config.php` on your machine. Set its existing database
   constants to these values, using your own password:

   ```php
   define('DB_NAME', 'wordpress');
   define('DB_USER', 'wordpress');
   define('DB_PASSWORD', 'replace-wordpress-password');
   define('DB_HOST', 'localhost');
   ```

   Generate unique authentication keys and salts as directed in the sample
   file. Keep this configuration out of version control. Before the line
   that loads `wp-settings.php`, also add:

   ```php
   define('DISALLOW_FILE_MODS', true);
   define('WP_AUTO_UPDATE_CORE', false);
   ```

   This setup manages code on the host, not through the dashboard. These
   settings disable dashboard code editing, plugin/theme installation and
   updates, and automatic core updates. See WordPress's
   [configuration reference](https://developer.wordpress.org/advanced-administration/wordpress/wp-config/).

3. Start WordPress with only uploads writable. Use the same application
   password as in `wp-config.php`:

   ```bash
   docker volume create lamp-wordpress-mysql
   docker run --detach --name lamp-wordpress --stop-timeout 75 \
     -p 127.0.0.1:8081:8080 \
     -e MYSQL_ADMIN_PASS='replace-admin-password' \
     -e MYSQL_USER_NAME=wordpress -e MYSQL_USER_DB=wordpress \
     -e MYSQL_USER_PASS='replace-wordpress-password' \
     --mount "type=bind,src=${PWD}/app,dst=/app,readonly" \
     --mount "type=bind,src=${PWD}/app/wp-content/uploads,dst=/app/wp-content/uploads" \
     --mount type=volume,src=lamp-wordpress-mysql,dst=/var/lib/mysql \
     "$LAMP_IMAGE"
   ```

4. Open `http://localhost:8081/` and complete WordPress's site setup. Upload
   a picture through the Media Library, then check that it appears under
   `app/wp-content/uploads` on your machine.

Edit themes and plugins locally and refresh the browser to view changes.
Install their files and apply security updates from the host as well; with
automatic updates disabled, keeping them current is your responsibility.

WordPress cannot write the read-only `.htaccess` file. If you enable pretty
permalinks, save the rules WordPress provides to `app/.htaccess` using your
editor. The image enables Apache's rewrite module and `.htaccess` support.

Caching plugins may need an additional writable directory such as
`wp-content/cache`, and some generate files directly under `wp-content`.
Follow that plugin's instructions, prepare any generated configuration on
the host where possible, and add only the specific mounts needed. This
example does not make all of `wp-content` writable or support dashboard
updates by silently relaxing permissions.

## Concrete CMS (concrete5)

Concrete CMS was previously called concrete5. Its
[system requirements](https://documentation.concretecms.org/9-x/developers/introduction/system-requirements)
list **Concrete 9.5 or later for PHP 8.5**. A site using an earlier concrete5
release needs a compatible upgrade before it can use this image. Check
add-on compatibility as well.

This example uses the downloadable release layout, with `app/index.php`
and `app/concrete/` directly under `app/`. A Composer project may put the web
root in `public/`; adjust `APACHE_ROOT` and all mount paths to match rather
than exposing the entire Composer project.

1. [Download Concrete CMS](https://www.concretecms.org/download) and extract
   the release into `app/`. Concrete's
   [installation guide](https://documentation.concretecms.org/9-x/developers/introduction/installing-concrete-cms)
   requires these directories to be writable:

   ```bash
   mkdir -p app/application/files app/application/config app/packages app/updates
   ```

   Keep the contents supplied by the release in those directories. Prepare
   their permissions and run the [write check](#checking-access-before-startup)
   for each one.

   | Directory | Why Concrete writes there |
   | --- | --- |
   | `application/files` | Uploaded files and the default file cache |
   | `application/config` | Database and site configuration, including generated settings |
   | `packages` | Installed add-ons and themes |
   | `updates` | Downloaded core updates |

2. Start the container with those four directories mounted separately:

   ```bash
   docker volume create lamp-concrete-mysql
   docker run --detach --name lamp-concrete --stop-timeout 75 \
     -p 127.0.0.1:8082:8080 \
     -e MYSQL_ADMIN_PASS='replace-admin-password' \
     -e MYSQL_USER_NAME=concrete -e MYSQL_USER_DB=concrete \
     -e MYSQL_USER_PASS='replace-concrete-password' \
     --mount "type=bind,src=${PWD}/app,dst=/app,readonly" \
     --mount "type=bind,src=${PWD}/app/application/files,dst=/app/application/files" \
     --mount "type=bind,src=${PWD}/app/application/config,dst=/app/application/config" \
     --mount "type=bind,src=${PWD}/app/packages,dst=/app/packages" \
     --mount "type=bind,src=${PWD}/app/updates,dst=/app/updates" \
     --mount type=volume,src=lamp-concrete-mysql,dst=/var/lib/mysql \
     "$LAMP_IMAGE"
   ```

3. Open `http://localhost:8082/` and follow the installer. Use database
   server `localhost`, database `concrete`, user `concrete`, and the
   application password from the command. Don't use the MySQL admin account
   as the site's database user.

4. Edit your site's code on the host. Uploaded files, generated configuration,
   and dashboard-installed packages are also saved to the host directories,
   so they survive container replacement. Keep credentials and runtime data
   out of version control and back them up with the database.

The writable configuration, packages, and updates directories can contain
executable PHP. This installer-friendly setup therefore allows more than
uploads and cache writes; it does not make all application code immutable.
If you manage packages and core updates on the host, you can remove their
writable mounts when recreating the container. Test that workflow with your
chosen release; dashboard installation and update features will no longer
be able to write there.

If Concrete asks to update `.htaccess` for pretty URLs, apply its rules to
`app/.htaccess` from your editor. Don't make `/app` writable for that change.
For public deployments, also review Concrete's
[configuration guidance](https://documentation.concretecms.org/9-x/developers/introduction/configuration-best-practices),
including private file storage and cache placement outside the web root.

## Stopping and backing up

Use the container name for your example, such as:

```bash
docker stop lamp-wordpress
docker start lamp-wordpress
```

Code changes on the host do not require these commands. If changes seem
missing, check application, plugin, browser, and PHP caching before assuming
the mount has failed.

For a replacement container with different mount options, stop and remove
the container first, then repeat its `docker run` command with the same
database volume. Never run two containers against the same MySQL data.
Back up both the database and application data before changing versions.
The [database backup tools](../README.md#backups-and-restores) do not back up
uploads, configuration, themes, or packages on your host.
