#!/usr/bin/env bash
# Forced command for the production CI deploy key. provision.sh installs the key in
# /root/.ssh/authorized_keys as
#   command="/srv/gynocamp/deploy/ssh-deploy.sh",restrict ssh-ed25519 AAAA... gynocamp-ci
# so that key can run nothing but this. The CI job pipes a tar.gz of the build
# artifacts and passes the commit sha as the command:
#   tar -C dist -czf - . | ssh root@<host> <sha>
set -euo pipefail

die() { echo "ssh-deploy: $*" >&2; exit 1; }

SHA=${SSH_ORIGINAL_COMMAND:-}
case "$SHA" in *[!0-9a-f]*|"") die "expected a 40-character commit sha as the command" ;; esac
[[ ${#SHA} -eq 40 ]] || die "commit sha must be 40 characters"

D=$(mktemp -d /srv/gynocamp/incoming.XXXXXX)
trap 'rm -rf "$D"' EXIT
tar -xzf - -C "$D" --no-same-owner --no-same-permissions
[[ $(cat "$D/BUILD_SHA" 2>/dev/null) == "$SHA" ]] || die "artifacts were not built from $SHA"

mkdir -p /srv/gynocamp/logs
exec > >(tee -a "/srv/gynocamp/logs/deploy-$(date +%Y-%m-%d-%H%M%S).log") 2>&1
echo "== deploy $SHA (ssh)"
bash /srv/gynocamp/deploy/install.sh "$D"
