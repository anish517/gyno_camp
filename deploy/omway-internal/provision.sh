#!/usr/bin/env bash
# One-time (idempotent) setup of a GynoCamp server. Run as root from a copy of
# this directory:
#   scp -r deploy/omway-internal <host>:/tmp/gynocamp-deploy
#   ssh <host> '[VAR=value ...] bash /tmp/gynocamp-deploy/provision.sh && rm -rf /tmp/gynocamp-deploy'
#
# Settings (environment variables). They are saved to /srv/gynocamp/deploy.env
# and read back on the next run, so a re-run never turns production into dev:
#   SERVER_NAME     nginx server_name; "_" = answer on the bare IP (default_server).
#                   Default gynocamp.omwaytechnologies.com (dev).
#   PUBLIC_URL      URL the web bundle is built for and the smoke test fetches.
#                   Default https://$SERVER_NAME.
#   DB              database name. Default gynocamp_dev.
#   RUNNER_SUDOERS  1 = install the sudo rule for a local GitLab runner (dev). Default 1.
#   BACKUP_BEFORE_DEPLOY  1 = install.sh dumps the database before each deploy. Default 0.
#
# Dev (omway-internal):  bash provision.sh
# Production (by IP):    SERVER_NAME=_ PUBLIC_URL=http://213.163.200.92 DB=gynocamp \
#                        RUNNER_SUDOERS=0 BACKUP_BEFORE_DEPLOY=1 bash provision.sh
#
# Re-run it whenever a file in deploy/omway-internal/ changes: it is the only thing
# that updates /srv/gynocamp/deploy, the units, the nginx site and the sudoers rule.
# Creates the database and env file only if missing; never rotates the password.
# TLS (needs a domain) is a separate, one-time step afterwards:
#   certbot --nginx -d <domain> --redirect
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APP=/srv/gynocamp
ROLE=gynocamp

[[ $EUID -eq 0 ]] || { echo "provision: must run as root" >&2; exit 1; }

# Explicit arguments win, then what this server was provisioned with last time, then dev defaults.
ARG_SERVER_NAME=${SERVER_NAME-} ARG_PUBLIC_URL=${PUBLIC_URL-} ARG_DB=${DB-}
ARG_RUNNER_SUDOERS=${RUNNER_SUDOERS-} ARG_BACKUP=${BACKUP_BEFORE_DEPLOY-}
# shellcheck source=/dev/null
[[ -f $APP/deploy.env ]] && . "$APP/deploy.env"
SERVER_NAME=${ARG_SERVER_NAME:-${SERVER_NAME:-gynocamp.omwaytechnologies.com}}
PUBLIC_URL=${ARG_PUBLIC_URL:-${PUBLIC_URL:-https://$SERVER_NAME}}
DB=${ARG_DB:-${DB:-gynocamp_dev}}
RUNNER_SUDOERS=${ARG_RUNNER_SUDOERS:-${RUNNER_SUDOERS:-1}}
BACKUP_BEFORE_DEPLOY=${ARG_BACKUP:-${BACKUP_BEFORE_DEPLOY:-0}}
echo "== settings: SERVER_NAME=$SERVER_NAME PUBLIC_URL=$PUBLIC_URL DB=$DB RUNNER_SUDOERS=$RUNNER_SUDOERS BACKUP_BEFORE_DEPLOY=$BACKUP_BEFORE_DEPLOY"

echo "== packages"
if ! command -v nginx >/dev/null || ! command -v psql >/dev/null || ! command -v rsync >/dev/null || ! command -v file >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q nginx postgresql rsync file curl openssl
fi

echo "== swap (small boxes only)"
if [[ -z $(swapon --show --noheadings) ]] && (( $(awk '/MemTotal/{print $2}' /proc/meminfo) < 2000000 )); then
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap -q /swapfile && swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "   added 2G /swapfile"
fi

echo "== firewall"
if command -v ufw >/dev/null && ufw status | grep -q 'Status: inactive'; then
    ufw allow OpenSSH >/dev/null && ufw allow 80/tcp >/dev/null && ufw allow 443/tcp >/dev/null
    ufw --force enable >/dev/null
    echo "   ufw enabled: 22, 80, 443"
fi

echo "== system user and directories"
id -u gynocamp >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin gynocamp
install -d -m 755 -o root -g root "$APP" "$APP/bin" "$APP/deploy"
install -d -m 750 -o root -g root "$APP/logs"
install -d -m 700 -o root -g root "$APP/backups"
[[ -d $APP/www ]] || install -d -m 755 -o root -g root "$APP/www"
cat > "$APP/deploy.env" <<EOF
SERVER_NAME='$SERVER_NAME'
PUBLIC_URL='$PUBLIC_URL'
DB='$DB'
RUNNER_SUDOERS='$RUNNER_SUDOERS'
BACKUP_BEFORE_DEPLOY='$BACKUP_BEFORE_DEPLOY'
EOF

echo "== deploy scripts -> $APP/deploy"
install -m 755 -o root -g root "$HERE/install.sh" "$HERE/ci-deploy.sh" "$HERE/backup.sh" "$APP/deploy/"

echo "== PostgreSQL role and database"
if [[ ! -f $APP/gynocamp.env ]]; then
    PW=$(openssl rand -hex 24)
    if sudo -u postgres psql -Atc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'" | grep -q 1; then
        sudo -u postgres psql -qc "ALTER ROLE $ROLE WITH LOGIN PASSWORD '$PW'"
    else
        sudo -u postgres psql -qc "CREATE ROLE $ROLE WITH LOGIN PASSWORD '$PW'"
    fi
    umask 077
    cat > "$APP/gynocamp.env" <<EOF
PORT=8080
HOST=127.0.0.1
PGHOST=127.0.0.1
PGPORT=5432
PGDATABASE=$DB
PGUSER=$ROLE
PGPASSWORD=$PW
EOF
    umask 022
    echo "   wrote $APP/gynocamp.env"
fi
chmod 600 "$APP/gynocamp.env"
sudo -u postgres psql -Atc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 \
    || sudo -u postgres createdb --owner="$ROLE" "$DB"

echo "== systemd units"
install -m 644 "$HERE/gynocamp-api.service" "$HERE/gynocamp-backup.service" "$HERE/gynocamp-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable gynocamp-api >/dev/null
systemctl enable --now gynocamp-backup.timer >/dev/null
# Starts only once a binary has been installed (install.sh restarts it on deploy).
[[ -x $APP/bin/gynocamp_server ]] && systemctl restart gynocamp-api

echo "== nginx site"
# Keep the certbot-managed version once TLS is set up; only seed the site the first time.
if [[ ! -f /etc/nginx/sites-available/gynocamp ]]; then
    sed "s/server_name gynocamp.omwaytechnologies.com;/server_name $SERVER_NAME;/" \
        "$HERE/nginx-gynocamp.conf" > /etc/nginx/sites-available/gynocamp
    if [[ $SERVER_NAME == _ ]]; then
        # Answer on the bare IP: become the default server instead of the stock site.
        sed -i 's/listen 80;/listen 80 default_server;/; s/listen \[::\]:80;/listen [::]:80 default_server;/' \
            /etc/nginx/sites-available/gynocamp
        rm -f /etc/nginx/sites-enabled/default
    fi
fi
ln -sfn /etc/nginx/sites-available/gynocamp /etc/nginx/sites-enabled/gynocamp
nginx -t
systemctl reload nginx

if [[ $RUNNER_SUDOERS == 1 ]]; then
    echo "== sudoers rule for the GitLab runner"
    install -m 440 -o root -g root "$HERE/sudoers-gitlab-runner-gynocamp" /etc/sudoers.d/gitlab-runner-gynocamp
    visudo -c -q || { rm -f /etc/sudoers.d/gitlab-runner-gynocamp; echo "provision: sudoers check failed, rule removed" >&2; exit 1; }
fi

echo "== provisioned"
