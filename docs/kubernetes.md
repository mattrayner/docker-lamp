# Kubernetes, storage, and recovery

The [Restricted template](../kubernetes/restricted-deployment.yaml) is a
one-replica all-in-one Pod. Before deployment, replace the image with an
approved immutable digest, provision the `lamp-mysql-data` PVC, and create a
`mysql-admin-password` Secret with a `password` key. The template deliberately
does not create either resource because credentials and storage classes are
cluster-specific.

It is Restricted-style: the Pod has `runAsNonRoot: true`,
`runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000`, and RuntimeDefault
seccomp. The container denies privilege escalation, drops `ALL` capabilities,
and has a read-only root filesystem. Writable `emptyDir` mounts are supplied
for `/run/lamp`, `/run/mysql`, and `/tmp`; the PVC is `/var/lib/mysql`.

The Service maps port `80` to container HTTP `8080` only. MySQL `3306` is not
published. Terminate public TLS at an Ingress or gateway and forward to `8080`.
The all-in-one database/web Pod is not horizontally scalable: retain one
replica and one writer for its data claim. The Deployment uses `Recreate`, so
an update deliberately has downtime while the old Pod terminates and the
replacement starts; it does not perform a rolling update with old/new Pods.
`terminationGracePeriodSeconds: 75` exceeds the runtime's 60-second cleanup
deadline so Supervisor can stop Apache and MySQL before kubelet sends SIGKILL.

`Recreate` is only Deployment-level sequencing, not storage fencing. It does
not stop manually created Pods, a stale node, forced deletion, or a storage
system that permits multiple writers. `ReadWriteOnce` is also not a substitute
for application/storage fencing in every failure mode. Keep one writer, avoid
manual duplicate Pods, and use an external fencing/operational recovery
procedure when the storage backend or failure model can permit split brain.

## Storage and Secret projection

### Simple path

Use a new dynamically provisioned `ReadWriteOnce` PVC, retain the three
runtime `emptyDir` mounts, and keep app code in the immutable image or mounted
read-only at `/app`. The template mounts the pre-provisioned `mysql`
subdirectory using `subPath: mysql`; it must be empty and writable by
`1000:1000` before the Pod starts. An empty PVC is initialized with the
explicitly projected `MYSQL_ADMIN_PASS_FILE` Secret. Do not share the claim or
attach another writer.

`fsGroup: 1000` asks kubelet to make compatible volume content usable by group
`1000`; it is not image-side ownership repair. `fsGroupChangePolicy:
OnRootMismatch` may avoid repeated volume ownership changes, but cannot make
an incompatible existing volume writable.

### Advanced path and limitations

For an existing PVC, CSI volume, NFS export, or writable app bind equivalent,
the operator must pre-provision directories writable by numeric `1000:1000`
(or an assigned compatible group). The image never runs `chown`, remaps IDs,
or uses a privileged init container. Repair a failure in the storage system,
not by weakening the Pod policy.

Some filesystem-backed claims contain `lost+found` at their root, making the
root unsuitable as a fresh MySQL data directory. The supported solution is the
template's `subPath: mysql`: before scheduling, the storage administrator
creates an empty `mysql` directory beneath the claim root and makes that
directory writable by `1000:1000` (or the compatible assigned group). The
image sees only that directory at `/var/lib/mysql`; it does not delete
`lost+found`, create the subdirectory, or repair ownership. If the subPath is
missing, non-empty, or unwritable, correct it out of band before startup.

`fsGroup` is kubelet/driver behavior. CSI drivers can omit or defer it; a large
existing volume may be slow to mount. NFS `root_squash`, server ACLs, SELinux
labels, and existing ownership can also deny access. Test the precise
StorageClass, driver version, and existing-volume path before production.

The template projects its password at `/run/secrets/mysql-admin/password` with
mode `0440`, then points `MYSQL_ADMIN_PASS_FILE` to it. It depends on
compatible `fsGroup` handling for readability by `1000:1000`. Secret volume
ownership and mode can vary with kubelet, admission mutation, and CSI Secret
stores. Verify a regular readable file as UID `1000` on the actual cluster. If
it fails, correct the projection or provider policy; do not run the image as
root. Selecting a broader Secret mode is a cluster-security decision.

## Ports, TLS, and isolation

Native TLS is optional: mount regular readable certificate/key files, set
`APACHE_TLS_ENABLED=1`, `APACHE_TLS_CERT_FILE`, and `APACHE_TLS_KEY_FILE`, and
map Service `443` to container `8443` only when deliberately using it.
External TLS termination avoids placing a private key in this Pod.

All Apache/PHP, MySQL, initialization, and backup processes use UID:GID
`1000:1000`. This enables Restricted execution but is **not service
isolation**: PHP can read mounted Secrets, including a readable TLS key, and
can access MySQL data. Web/database or Secret isolation requires separate web
and database deployments with separate identities and Secrets; there is no
supported in-image identity exception.

## Migration and recovery lifecycle

Use logical backup/restore; never copy a live data directory or mount a 20.04
MySQL data directory into a current image. Back up before changing storage,
image generation, identity, or Kubernetes driver. The following commands are
the only migration commands documented here because the rootless fixture
exercises their underlying binaries. Replace `CONTAINER` and `DATABASE`; on
Kubernetes use the same binaries through an approved exec workflow.

```bash
docker exec CONTAINER env MYSQL_ADMIN_PASS_FILE=/run/secrets/mysql-admin/password \
  docker-lamp-backup --database DATABASE > DATABASE.sql

docker exec -i CONTAINER env MYSQL_ADMIN_PASS_FILE=/run/secrets/mysql-admin/password \
  docker-lamp-restore --database DATABASE < DATABASE.sql
```

Restore requires an existing target database, is neither transactional nor
database-confined, and accepts trusted SQL only. Test the backup/restore pair;
logical dumps retain normal concurrent-DDL and non-transactional-table limits.

`ready` volumes skip account mutation and initialization-import replay. Legacy
volumes (data present but no lifecycle marker) also start without account or
import changes: back them up, then migrate to a fresh provisioned volume.
`initializing` or inconsistent volumes fail closed. Do not remove the marker to
force a restart; investigate the interrupted source and recover a tested
logical backup into a fresh volume with explicit credentials.

Initialization imports run only on a fresh volume, in lexical order from
`/docker-entrypoint-initdb.d`; they are not recovery. Supply exactly one of
`MYSQL_ADMIN_PASS` or `MYSQL_ADMIN_PASS_FILE`. Later environment values do not
change an existing volume's credentials.

User PHP `.ini` overrides mount at `/etc/docker-lamp/php/conf.d:ro`. Set
`PHP_USER_OVERRIDES_DISABLED=1` to bypass that directory only during recovery.
Xdebug is off by default; `XDEBUG_ENABLED=1`, plus standard `XDEBUG_MODE` and
`XDEBUG_CONFIG`, enables it for Apache, CLI, Composer, and the `php` wrapper.

MySQL defaults to literal loopback `MYSQL_BIND_ADDRESS=127.0.0.1`; the template
does not publish `3306`. Allow a peer only with an explicit Service and network
policy and a supported literal (for example `0.0.0.0`) on first initialization.
That changes the first-run application-account host policy, not existing
accounts. Do not expose MySQL merely for backup or migration.

## Automated-coverage map

There is no Kubernetes cluster fixture, so this repository does not claim that
`kubectl apply` is exercised. [`tests/test-kubernetes-manifest.sh`](../tests/test-kubernetes-manifest.sh)
statically checks the manifest's Restricted fields, writable mounts,
Secret-file wiring, and guide requirements. Operators must validate admission,
CSI/NFS behavior, Secret projection, and PVC ownership in their cluster.

| Path or command | Existing automated coverage |
| --- | --- |
| Restricted manifest contract | [`test-kubernetes-manifest.sh`](../tests/test-kubernetes-manifest.sh) |
| Fresh persistent volume | `run_persistent_shutdown_fixture` in [`test-rootless-runtime.sh`](../tests/test-rootless-runtime.sh) |
| Unsupported/unwritable driver or permissions | `run_denied_mount_fixture` in [`test-rootless-runtime.sh`](../tests/test-rootless-runtime.sh) |
| Pre-provisioned writable bind-style storage | `run_restricted_source_fixture` in [`test-rootless-runtime.sh`](../tests/test-rootless-runtime.sh) |
| Interrupted and legacy MySQL | `run_mysql_lifecycle_fixture`, `run_ready_legacy_state_fixture` |
| Explicit credentials and first-run imports | `run_mysql_credential_fixture`, `run_import_manifest_fixture` |
| Bind policy | `run_mysql_bind_fixture` |
| TLS, PHP bypass/Xdebug, backup/restore | `run_phase3_transport_php_backup_fixture` |

The last four fixture names are in
[`tests/test-rootless-runtime.sh`](../tests/test-rootless-runtime.sh). Run the
supported coverage where Docker is available:

```bash
RUN_ROOTLESS_RUNTIME_TESTS=1 ./tests/test.sh
```

It requires `DOCKER_DEFAULT_PLATFORM` as described in the
[README](../README.md#development).
