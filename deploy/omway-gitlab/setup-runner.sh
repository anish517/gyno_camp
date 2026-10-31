#!/usr/bin/env bash
# One-time (idempotent) setup of the Flutter build runner on omway-gitlab. Run as root:
#   scp -r deploy/omway-gitlab omway-gitlab:/tmp/gynocamp-runner
#   ssh omway-gitlab 'bash /tmp/gynocamp-runner/setup-runner.sh && rm -rf /tmp/gynocamp-runner'
# Then register it once (token from GitLab: project > Settings > CI/CD > Runners >
# New project runner, tag "flutter-build", "Run untagged jobs" unchecked):
#   gitlab-runner register --non-interactive --url https://gitlab.omwaytech.com \
#     --token glrt-XXXX --executor shell --name omway-gitlab-flutter
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
FLUTTER_VERSION=3.47.1     # keep in step with the SDK the team builds with
FLUTTER_DIR=/home/gitlab-runner/flutter

[[ $EUID -eq 0 ]] || { echo "setup-runner: must run as root" >&2; exit 1; }

echo "== packages"
if ! command -v gitlab-runner >/dev/null; then
    curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
    DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-runner
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip xz-utils git curl >/dev/null

echo "== one job at a time"
CFG=/etc/gitlab-runner/config.toml
if [[ -f $CFG ]] && grep -q '^concurrent' "$CFG"; then
    sed -i 's/^concurrent = .*/concurrent = 1/' "$CFG"
fi

echo "== resource limits for builds"
install -d /etc/systemd/system/gitlab-runner.service.d
install -m 644 "$HERE/gitlab-runner-limits.conf" /etc/systemd/system/gitlab-runner.service.d/limits.conf
systemctl daemon-reload
systemctl restart gitlab-runner

echo "== Flutter $FLUTTER_VERSION in $FLUTTER_DIR"
cd /home/gitlab-runner   # flutter's first run fails if cwd is unreadable (e.g. /root)
if [[ $(git -C "$FLUTTER_DIR" describe --tags --exact-match 2>/dev/null) != "$FLUTTER_VERSION" ]]; then
    rm -rf "$FLUTTER_DIR"
    sudo -u gitlab-runner git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
sudo -u gitlab-runner -H env CI=true "$FLUTTER_DIR/bin/flutter" config --no-analytics --no-cli-animations >/dev/null
sudo -u gitlab-runner -H env CI=true "$FLUTTER_DIR/bin/flutter" precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
sudo -u gitlab-runner -H "$FLUTTER_DIR/bin/flutter" --version

echo "== production deploy key (used by deploy:production)"
# The private key never leaves this host. Print the public half and install it on
# production with provision.sh's CI_DEPLOY_KEY, which restricts it to ssh-deploy.sh.
PROD_HOST=213.163.200.92
K=/home/gitlab-runner/.ssh/gynocamp_production
install -d -m 700 -o gitlab-runner -g gitlab-runner /home/gitlab-runner/.ssh
[[ -f $K ]] || sudo -u gitlab-runner ssh-keygen -q -t ed25519 -N "" -C "gynocamp-ci@omway-gitlab" -f "$K"
sudo -u gitlab-runner sh -c "ssh-keyscan -t ed25519 $PROD_HOST > $K""_known_hosts 2>/dev/null"
echo "   public key: $(cat "$K.pub")"

echo "== runner ready; registered runners:"
gitlab-runner list 2>&1 | tail -n +2 || true
