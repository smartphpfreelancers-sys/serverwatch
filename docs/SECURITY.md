# Deployment security

This guide covers running ServerWatch safely on an internet-facing host. For
reporting a vulnerability, see [SECURITY.md](../SECURITY.md) at the repository
root.

## Threat model

A default ServerWatch install is designed for a trusted LAN: the dashboard and
its API are **open** unless authentication is enabled. That is convenient for a
first look, but on a public IP it means anyone who can reach the port can view
and change your monitors.

The two things worth protecting are:

- **The admin dashboard and `/api/` routes** - full read/write access to
  monitors, groups, and settings.
- **The public status page** (`/status`) - intentionally public and read-only.
  It renders only monitor names, derived state, response time, and last check
  time; never targets, ports, or configuration.

## Recommended posture

| Control | Setting | Why |
| --- | --- | --- |
| Account authentication | `SERVERWATCH_AUTH_ENABLED=true` | Requires a login session for `/api/` |
| Secure cookies | `SERVERWATCH_COOKIE_SECURE=true` | Only after HTTPS works (see below) |
| Public status page | `SERVERWATCH_STATUS_PAGE_ENABLED=true` | Expose only `/status`, not the admin UI |
| Reverse proxy | Nginx config in `deployments/nginx/` | Edge rate limiting + security headers |
| TLS | Certbot / your certificate | Encrypts the session cookie in transit |
| Secrets | `0600` environment file | Nothing sensitive in git or images |

Authentication guards only the `/api/` prefix. `/health`, `/ready`, and the
opt-in `/status` page stay reachable without a session so probes and public
status keep working.

## Quick hardening

From a checkout of the repository, as root:

```bash
sudo scripts/harden-server.sh
```

The script is idempotent and backs up everything it touches. It:

1. Backs up the environment file and the Nginx site configuration.
2. Sets `SERVERWATCH_AUTH_ENABLED=true` and
   `SERVERWATCH_STATUS_PAGE_ENABLED=true`.
3. Restarts the service and waits for it to become ready.
4. Claims the first administrator account with a generated password and writes
   the credentials to `/root/serverwatch-admin-credentials.txt` (mode `0600`).
5. Installs the hardened Nginx configuration from
   `deployments/nginx/serverwatch.conf` and reloads Nginx.

Overridable variables: `SERVERWATCH_APP_DIR`, `SERVERWATCH_ENV_FILE`,
`SERVERWATCH_SERVICE`, `SERVERWATCH_BASE_URL`, `SERVERWATCH_ADMIN_EMAIL`,
`SERVERWATCH_NGINX_SITE`, `SERVERWATCH_SKIP_NGINX`.

### What remains manual

- **TLS**: obtain a certificate and set `SERVERWATCH_COOKIE_SECURE=true`. Until
  HTTPS is in place, leave it `false` or the browser will not return the session
  cookie over plain HTTP. See the "HTTPS / TLS" section at the bottom of
  `deployments/nginx/serverwatch.conf`.
- **Change the generated password** after the first login, then delete
  `/root/serverwatch-admin-credentials.txt`.

## Doing it by hand

If you prefer not to run the script:

```bash
# 1. Enable authentication and the read-only status page.
sudo sed -i 's/^SERVERWATCH_AUTH_ENABLED=.*/SERVERWATCH_AUTH_ENABLED=true/' \
  /opt/serverwatch/serverwatch.env
sudo sed -i 's/^SERVERWATCH_STATUS_PAGE_ENABLED=.*/SERVERWATCH_STATUS_PAGE_ENABLED=true/' \
  /opt/serverwatch/serverwatch.env
grep -q '^SERVERWATCH_AUTH_ENABLED=' /opt/serverwatch/serverwatch.env || \
  echo 'SERVERWATCH_AUTH_ENABLED=true' | sudo tee -a /opt/serverwatch/serverwatch.env

# 2. Restart the service.
sudo systemctl restart serverwatch

# 3. Claim the first administrator at the dashboard, or via the API:
curl -X POST http://127.0.0.1:8080/api/v1/auth/setup \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com","password":"a-strong-password","display_name":"Administrator"}'
```

The first administrator can only be created while no account exists. `setup`
never adds extra users or takes over an initialized install.

## Verify

```bash
# The API now requires a session.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/v1/monitors   # 401

# The public status page still answers.
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/status             # 200

# From outside, only the status page and health probes are reachable.
curl -s -o /dev/null -w '%{http_code}\n' http://YOUR_HOST/status                  # 200
```

If your Nginx config does not route `/status`, the SPA fallback serves the
dashboard instead. Install `deployments/nginx/serverwatch.conf` (the script does
this) so `/status` and `/status.css` reach the backend.

## Rollback

```bash
# Restore the environment file and service.
sudo cp /opt/serverwatch/serverwatch.env.bak.<timestamp> /opt/serverwatch/serverwatch.env
sudo systemctl restart serverwatch

# Restore the Nginx site.
sudo cp /etc/nginx/sites-available/serverwatch.bak.<timestamp> /etc/nginx/sites-available/serverwatch
sudo nginx -t && sudo systemctl reload nginx
```

## Prefer a firewall instead?

If you would rather run unauthenticated on a trusted network, restrict access at
the edge instead:

```bash
# Allow only your own address to reach the dashboard.
sudo ufw allow from YOUR.IP.ADDR.HERE to any port 80 proto tcp
sudo ufw allow 22/tcp
sudo ufw enable
```

Authentication and a firewall are complementary; do not rely on the firewall
alone if the host is ever reachable from an untrusted network.

## Secrets

- Keep the environment file at `0600`, owned by the service user.
- Never commit `serverwatch.env`; `.gitignore` and `.dockerignore` already
  exclude it.
- Prefer a password manager or your platform's secret store for SMTP, Telegram,
  and database credentials.
