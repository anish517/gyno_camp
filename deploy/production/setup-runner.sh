#!/usr/bin/env bash
# One-time (idempotent) setup of the deploy-only GitLab runner on the production
# box (213.163.200.92). Run as root:
#   scp deploy/production/setup-runner.sh root@213.163.200.92:/tmp/
#   ssh root@213.163.200.92 'bash /tmp/setup-runner.sh && rm /tmp/setup-runner.sh'
# Then register it once. In GitLab: project > Settings > CI/CD > Runners > New
# project runner, tag "gynocamp-production", "Run untagged jobs" OFF, "Protected"
# ON, "Lock to current projects" ON; then on the box:
#   gitlab-runner register --non-interactive --url https://gitlab.omwaytech.com \
#     --token glrt-XXXX --executor shell --name gynocamp-production
#
# Why this is safe: a Protected runner only receives jobs from protected branches,
# and PRODUCTION is protected, so code from a merge request never runs here. The
# only job it runs is deploy:production, which can do exactly one thing as root:
#   sudo /srv/gynocamp/deploy/ci-deploy.sh
# (the sudo rule comes from provision.sh with RUNNER_SUDOERS=1).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "setup-runner: must run as root" >&2; exit 1; }

if ! command -v gitlab-runner >/dev/null; then
    echo "== install gitlab-runner (official binary, checksum-verified)"
    # The packages.gitlab.com apt repo can lag new Ubuntu releases; the binary works everywhere.
    BASE=https://gitlab-runner-downloads.s3.amazonaws.com/latest
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    curl -fsSL -o "$T/gitlab-runner-linux-amd64" "$BASE/binaries/gitlab-runner-linux-amd64"
    curl -fsSL -o "$T/release.sha256" "$BASE/release.sha256"
    SUM=$(awk '{f=$2; sub(/^\*/, "", f)} f == "binaries/gitlab-runner-linux-amd64" {print $1}' "$T/release.sha256")
    [[ -n $SUM ]] || { echo "setup-runner: no checksum for the binary in release.sha256" >&2; exit 1; }
    echo "$SUM  $T/gitlab-runner-linux-amd64" | sha256sum -c -
    install -m 755 "$T/gitlab-runner-linux-amd64" /usr/local/bin/gitlab-runner
    id -u gitlab-runner >/dev/null 2>&1 || useradd --comment 'GitLab Runner' --create-home --shell /bin/bash gitlab-runner
    gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
fi

# Ubuntu's skeleton .bash_logout runs clear_console, which makes every shell-executor
# job fail in "prepare environment".
rm -f /home/gitlab-runner/.bash_logout

echo "== one job at a time, small memory cap"
CFG=/etc/gitlab-runner/config.toml
if [[ -f $CFG ]] && grep -q '^concurrent' "$CFG"; then
    sed -i 's/^concurrent = .*/concurrent = 1/' "$CFG"
fi
install -d /etc/systemd/system/gitlab-runner.service.d
cat > /etc/systemd/system/gitlab-runner.service.d/limits.conf <<'EOF'
# The box has 842 MB of RAM and serves the app; the runner only unpacks artifacts.
[Service]
MemoryMax=256M
EOF
systemctl daemon-reload
systemctl enable --now gitlab-runner >/dev/null
systemctl restart gitlab-runner

echo "== $(gitlab-runner --version | head -1)"
gitlab-runner list 2>&1 | tail -n +2 || true
