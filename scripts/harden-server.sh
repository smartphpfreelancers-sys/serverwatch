#!/usr/bin/env bash
#
# ServerWatch Community Edition — host security hardening.
#
# Makes a fresh, internet-facing install safe:
#
#   1. Backs up the environment file and the Nginx site configuration.
#   2. Enables account authentication (SERVERWATCH_AUTH_ENABLED=true) so the
#      dashboard and the /api/ routes require a session.
#   3. Enables the read-only public status page
#      (SERVERWATCH_STATUS_PAGE_ENABLED=true), which exposes only monitor names,
#      state, response time, and last check time - never targets or config.
#   4. Restarts the service and waits for it to become ready.
#   5. Claims the first administrator account with a generated password and
#      writes the credentials to a root-only file.
#   6. Installs the hardened Nginx reverse-proxy configuration from
#      deployments/nginx/serverwatch.conf (edge rate limiting, security
#      headers, and /status and /status.css routing) and reloads Nginx.
#
# It is idempotent: re-running it will not overwrite an existing administrator,
# will not duplicate environment entries, and will only rewrite the Nginx site
# when the content actually differs. Every destructive step is backed up first
# and restored if validation fails.
#
# Usage:
#   sudo scripts/harden-server.sh
#
# Environment overrides:
#   SERVERWATCH_APP_DIR      install directory            (default /opt/serverwatch)
#   SERVERWATCH_ENV_FILE     environment file             (default <APP_DIR>/serverwatch.env)
#   SERVERWATCH_SERVICE      systemd unit name            (default serverwatch)
#   SERVERWATCH_BASE_URL     backend base URL             (default http://127.0.0.1:8080)
#   SERVERWATCH_ADMIN_EMAIL  administrator email          (default admin@serverwatch.local)
#   SERVERWATCH_NGINX_SITE   Nginx site file              (default /etc/nginx/sites-available/serverwatch)
#   SERVERWATCH_SKIP_NGINX   set to 1 to skip Nginx steps
#
set -euo pipefail

APP_DIR="${SERVERWATCH_APP_DIR:-/opt/serverwatch}"
ENV_FILE="${SERVERWATCH_ENV_FILE:-$APP_DIR/serverwatch.env}"
SERVICE="${SERVERWATCH_SERVICE:-serverwatch}"
BASE_URL="${SERVERWATCH_BASE_URL:-http://127.0.0.1:8080}"
ADMIN_EMAIL="${SERVERWATCH_ADMIN_EMAIL:-admin@serverwatch.local}"
NGINX_SITE="${SERVERWATCH_NGINX_SITE:-/etc/nginx/sites-available/serverwatch}"
SKIP_NGINX="${SERVERWATCH_SKIP_NGINX:-0}"
CREDENTIALS_FILE="${SERVERWATCH_CREDENTIALS_FILE:-/root/serverwatch-admin-credentials.txt}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_TEMPLATE="$REPO_ROOT/deployments/nginx/serverwatch.conf"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
log()  { printf '%s %s\n' "[harden]" "$*"; }
warn() { printf '%s %s\n' "[harden][warn]" "$*" >&2; }
die()  { printf '%s %s\n' "[harden][error]" "$*" >&2; exit 1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "must run as root (try: sudo $0)"
  fi
}

# upsert_env KEY VALUE FILE - set KEY=VALUE, replacing an existing line or
# appending it when missing. The match is anchored and uses | as the sed
# delimiter so values containing / do not need escaping.
upsert_env() {
  local key="$1" value="$2" file="$3"
  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >>"$file"
  fi
}

env_value() {
  local key="$1" file="$2"
  sed -n -E "s|^${key}=(.*)|\1|p" "$file" | head -n1
}

wait_for_ready() {
  local tries=30
  while [ "$tries" -gt 0 ]; do
    if curl -fsS "$BASE_URL/health" >/dev/null 2>&1; then
      return 0
    fi
    tries=$((tries - 1))
    sleep 1
  done
  return 1
}

main() {
  require_root
  [ -f "$ENV_FILE" ] || die "environment file not found: $ENV_FILE"
  command -v curl >/dev/null 2>&1 || die "curl is required"

  log "install directory : $APP_DIR"
  log "environment file  : $ENV_FILE"
  log "service           : $SERVICE"

  # -- 1. Back up the environment file ------------------------------------
  ENV_BACKUP="${ENV_FILE}.bak.${STAMP}"
  cp -p "$ENV_FILE" "$ENV_BACKUP"
  chmod 600 "$ENV_BACKUP" 2>/dev/null || true
  log "backed up environment file -> $ENV_BACKUP"

  if [ "$(env_value SERVERWATCH_COOKIE_SECURE "$ENV_FILE")" = "true" ]; then
    warn "SERVERWATCH_COOKIE_SECURE=true requires HTTPS; session cookies will"
    warn "not be sent over plain HTTP. Set up TLS or set it to false."
  fi

  # -- 2/3. Enable authentication and the read-only status page ------------
  upsert_env SERVERWATCH_AUTH_ENABLED "true" "$ENV_FILE"
  upsert_env SERVERWATCH_STATUS_PAGE_ENABLED "true" "$ENV_FILE"
  log "enabled SERVERWATCH_AUTH_ENABLED and SERVERWATCH_STATUS_PAGE_ENABLED"

  # -- 4. Restart and wait for readiness ----------------------------------
  log "restarting $SERVICE ..."
  systemctl restart "$SERVICE"
  if ! wait_for_ready; then
    warn "service did not become ready; restoring previous environment file"
    cp -p "$ENV_BACKUP" "$ENV_FILE"
    systemctl restart "$SERVICE" || true
    die "service failed to start after enabling authentication"
  fi
  log "service is ready"

  # -- 5. Claim the first administrator account ---------------------------
  local status_json setup_required
  status_json="$(curl -fsS "$BASE_URL/api/v1/auth/status" 2>/dev/null || true)"
  if printf '%s' "$status_json" | grep -q '"setup_required":true'; then
    local password raw http_code
    raw="$(dd if=/dev/urandom bs=256 count=1 2>/dev/null)"
    password="$(printf '%s' "$raw" | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24)"
    [ "${#password}" -ge 8 ] || die "failed to generate an administrator password"

    http_code="$(curl -s -o /tmp/sw-setup-response.json -w '%{http_code}' \
      -X POST "$BASE_URL/api/v1/auth/setup" \
      -H 'Content-Type: application/json' \
      --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${password}\",\"display_name\":\"Administrator\"}")"
    rm -f /tmp/sw-setup-response.json

    if [ "$http_code" = "201" ]; then
      ( umask 077; cat >"$CREDENTIALS_FILE" <<EOF
ServerWatch administrator credentials
Generated: ${STAMP}

Email:    ${ADMIN_EMAIL}
Password: ${password}

Sign in at the dashboard, then change this password. Store it in your
password manager and delete this file once it is saved somewhere safe.
EOF
      )
      chmod 600 "$CREDENTIALS_FILE"
      log "created administrator account: $ADMIN_EMAIL"
      log "credentials written to: $CREDENTIALS_FILE"
    else
      warn "administrator setup returned HTTP $http_code; claim it manually at the dashboard"
    fi
  else
    log "an administrator account already exists; leaving it unchanged"
  fi

  # -- 6. Install the hardened Nginx configuration ------------------------
  if [ "$SKIP_NGINX" = "1" ]; then
    warn "SERVERWATCH_SKIP_NGINX=1 set; skipping Nginx configuration"
  elif [ ! -f "$NGINX_TEMPLATE" ]; then
    warn "Nginx template not found at $NGINX_TEMPLATE; skipping Nginx configuration"
  elif ! command -v nginx >/dev/null 2>&1; then
    warn "nginx is not installed; skipping Nginx configuration"
  else
    install_nginx
  fi

  # -- Summary ------------------------------------------------------------
  printf '\n'
  log "hardening complete"
  log "sign in at the dashboard, then set SERVERWATCH_COOKIE_SECURE=true once TLS is enabled"
  log "environment file backup: $ENV_BACKUP"
}

install_nginx() {
  [ -f "$NGINX_SITE" ] || die "Nginx site not found: $NGINX_SITE (set SERVERWATCH_NGINX_SITE)"
  grep -qi "serverwatch" "$NGINX_SITE" || die "$NGINX_SITE does not look like a ServerWatch site; refusing to overwrite"

  if [ ! -f "$NGINX_TEMPLATE" ]; then
    warn "missing template; leaving Nginx unchanged"
    return 0
  fi

  local rendered="/tmp/serverwatch-nginx.$$"
  # Install the maintained template and point it at the configured install dir.
  sed "s#/opt/serverwatch#${APP_DIR}#g" "$NGINX_TEMPLATE" >"$rendered"

  if cmp -s "$rendered" "$NGINX_SITE"; then
    log "Nginx site already up to date; no reload needed"
    rm -f "$rendered"
    return 0
  fi

  local backup="${NGINX_SITE}.bak.${STAMP}"
  cp -p "$NGINX_SITE" "$backup"
  log "backed up Nginx site -> $backup"

  cp "$rendered" "$NGINX_SITE"
  rm -f "$rendered"

  if [ -d /etc/nginx/sites-enabled ]; then
    ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/serverwatch
  fi

  if nginx -t; then
    systemctl reload nginx || systemctl restart nginx
    log "Nginx configuration installed and reloaded"
  else
    warn "nginx -t failed; restoring previous configuration"
    cp -p "$backup" "$NGINX_SITE"
    rm -f "$rendered"
    die "Nginx configuration was invalid and has been rolled back"
  fi
}

main "$@"
