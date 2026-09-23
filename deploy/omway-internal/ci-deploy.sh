#!/usr/bin/env bash
# Entry point for the GitLab deploy job, allowed by /etc/sudoers.d/gitlab-runner-gynocamp:
#   sudo /srv/gynocamp/deploy/ci-deploy.sh "$CI_PROJECT_DIR/dist" "$CI_COMMIT_SHA"
# Checks that the artifacts come from a runner build dir and were built from the
# pipeline's commit, then hands over to install.sh.
#
# The scripts in /srv/gynocamp/deploy are installed by provision.sh and are NOT
# updated from the checkout, so pushing to the repo cannot change what runs as
# root here. Re-run provision.sh after editing anything in deploy/omway-internal/.
set -euo pipefail

DIST=${1:?usage: ci-deploy.sh <artifact-dir> <commit-sha>}
SHA=${2:?usage: ci-deploy.sh <artifact-dir> <commit-sha>}
BUILDS=/home/gitlab-runner/builds

die() { echo "ci-deploy: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (via sudo)"
case "$SHA" in *[!0-9a-f]*|"") die "commit sha is not hex: $SHA" ;; esac
[[ ${#SHA} -eq 40 ]] || die "commit sha must be 40 characters"
DIST=$(realpath -e -- "$DIST") || die "artifact dir does not exist"
[[ $DIST == "$BUILDS"/* ]] || die "artifacts must live under $BUILDS, got $DIST"
[[ $(cat "$DIST/BUILD_SHA" 2>/dev/null) == "$SHA" ]] || die "artifacts were not built from $SHA"

mkdir -p /srv/gynocamp/logs
exec > >(tee -a "/srv/gynocamp/logs/deploy-$(date +%Y-%m-%d-%H%M%S).log") 2>&1
echo "== deploy $SHA from $DIST"
bash /srv/gynocamp/deploy/install.sh "$DIST"
