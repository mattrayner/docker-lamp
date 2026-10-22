#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
manifest="${PROJECT_ROOT}/kubernetes/restricted-deployment.yaml"
guide="${PROJECT_ROOT}/docs/kubernetes.md"

require_manifest() {
    local expected=$1
    grep -Fqx -- "${expected}" "${manifest}" >/dev/null \
        || { printf 'missing Kubernetes manifest contract: %s\n' "${expected}" >&2; exit 1; }
}

[[ -f "${manifest}" && -f "${guide}" ]] \
    || { printf '%s\n' 'Kubernetes manifest or guide is missing' >&2; exit 1; }

require_manifest '        runAsNonRoot: true'
require_manifest '        runAsUser: 1000'
require_manifest '        runAsGroup: 1000'
require_manifest '        fsGroup: 1000'
require_manifest '  strategy:'
require_manifest '    type: Recreate'
require_manifest '      terminationGracePeriodSeconds: 75'
require_manifest '          type: RuntimeDefault'
require_manifest '            allowPrivilegeEscalation: false'
require_manifest '            readOnlyRootFilesystem: true'
require_manifest '                - ALL'
require_manifest '              mountPath: /run/lamp'
require_manifest '              mountPath: /run/mysql'
require_manifest '              mountPath: /tmp'
require_manifest '              mountPath: /var/lib/mysql'
require_manifest '              subPath: mysql'
require_manifest '              value: /run/secrets/mysql-admin/password'
require_manifest '            defaultMode: 0440'
require_manifest '      targetPort: http'

for expected in \
    'fsGroup' \
    'CSI' \
    'NFS' \
    'Secret projection' \
    'Recreate' \
    'fencing' \
    'terminationGracePeriodSeconds: 75' \
    'lost+found' \
    'subPath: mysql' \
    'separate web' \
    'PHP_USER_OVERRIDES_DISABLED=1' \
    'XDEBUG_ENABLED=1' \
    'docker-lamp-backup --database DATABASE' \
    'docker-lamp-restore --database DATABASE'; do
    grep -Fq -- "${expected}" "${guide}" >/dev/null \
        || { printf 'missing Kubernetes guide coverage: %s\n' "${expected}" >&2; exit 1; }
done

printf '%s\n' 'Kubernetes manifest and guide contract checks passed.'
