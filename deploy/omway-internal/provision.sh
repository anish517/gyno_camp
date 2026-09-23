#!/usr/bin/env bash
# One-time (idempotent) setup of GynoCamp dev on omway-internal. Run as root from a
# copy of this directory:
#   scp -r deploy/omway-internal omway-internal:/tmp/gynocamp-deploy
#   ssh omway-internal 'bash /tmp/gynocamp-deploy/provision.sh && rm -rf /tmp/gynocamp-deploy'
# Re-run it whenever a file in deploy/omway-internal/ changes: it is the only thing
# that updates /srv/gynocamp/deploy, the unit, the nginx site and the sudoers rule.
# Creates the database and env file only if missing; never rotates the password.
# TLS is a separate, one-time step afterwards:
#   certbot --nginx -d gynocamp.omwaytechnologies.com --redirect
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APP=/srv/gynocamp
DB=gynocamp_dev
ROLE=gynocamp

[[ $EUID -eq 0 ]] || { echo "provision: must run as root" >&2; exit 1; }

echo "== system user and directories"
id -u gynocamp >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin gynocamp
install -d -m 755 -o root -g root "$APP" "$APP/bin" "$APP/deploy"
install -d -m 750 -o root -g root "$APP/logs"
[[ -d $APP/www ]] || install -d -m 755 -o root -g root "$APP/www"

echo "== deploy scripts -> $APP/deploy"
install -m 755 -o root -g root "$HERE/install.sh" "$HERE/ci-deploy.sh" "$APP/deploy/"

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

echo "== systemd unit"
install -m 644 "$HERE/gynocamp-api.service" /etc/systemd/system/gynocamp-api.service
systemctl daemon-reload
systemctl enable gynocamp-api >/dev/null
# Starts only once a binary has been installed (install.sh restarts it on deploy).
[[ -x $APP/bin/gynocamp_server ]] && systemctl restart gynocamp-api

echo "== nginx site"
# Keep the certbot-managed version once TLS is set up; only seed the site the first time.
if [[ ! -f /etc/nginx/sites-available/gynocamp ]]; then
    install -m 644 "$HERE/nginx-gynocamp.conf" /etc/nginx/sites-available/gynocamp
fi
ln -sfn /etc/nginx/sites-available/gynocamp /etc/nginx/sites-enabled/gynocamp
nginx -t
systemctl reload nginx

echo "== sudoers rule for the GitLab runner"
install -m 440 -o root -g root "$HERE/sudoers-gitlab-runner-gynocamp" /etc/sudoers.d/gitlab-runner-gynocamp
visudo -c -q || { rm -f /etc/sudoers.d/gitlab-runner-gynocamp; echo "provision: sudoers check failed, rule removed" >&2; exit 1; }

echo "== provisioned"
