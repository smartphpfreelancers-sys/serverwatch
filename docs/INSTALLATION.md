# Installation

ServerWatch Community Edition runs as a single Go backend plus a Postgres
container. The dashboard is static files served by Nginx, Caddy, or another web
server.

## 1. Unpack the release

```bash
tar xzf serverwatch-v0.1.0-linux-amd64.tar.gz
sudo mv serverwatch-v0.1.0-linux-amd64 /opt/serverwatch
cd /opt/serverwatch
```

The bundle contains the `bin/serverwatch` backend, the built dashboard under
`web/dist`, database migrations, deployment templates, docs, and backup scripts.

## 2. Configure

```bash
cp .env.example serverwatch.env
chmod 600 serverwatch.env
```

Set at minimum `DATABASE_URL`. See [CONFIGURATION.md](CONFIGURATION.md) for the
full reference, including SMTP and Telegram alerts, authentication, retention,
and metrics.

## 3. Start Postgres

```bash
docker compose --env-file serverwatch.env up -d postgres
```

The backend applies pending migrations from the embedded copy on startup, so no
manual step is required.

## 4. Run the backend

```bash
./bin/serverwatch
```

Confirm it is healthy:

```bash
curl -s http://127.0.0.1:8080/health   # {"status":"ok","version":"v0.1.0",...}
curl -s http://127.0.0.1:8080/ready    # {"status":"ok","database":"ok",...}
```

## 5. Install as a service

```bash
sudo cp deployments/systemd/serverwatch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now serverwatch
```

The unit reads `/opt/serverwatch/serverwatch.env` and starts Postgres first.

## 6. Serve the dashboard

Choose either Nginx or Caddy. Both templates serve the dashboard, route API and
status-page requests to the backend, and leave health probes public.

### Nginx

```bash
sudo cp deployments/nginx/serverwatch.conf /etc/nginx/sites-available/serverwatch
sudo ln -s /etc/nginx/sites-available/serverwatch /etc/nginx/sites-enabled/serverwatch
sudo nginx -t && sudo systemctl reload nginx
```

Nginx serves `web/dist`, proxies `/api`, and terminates TLS. See the HTTPS
section at the bottom of the Nginx template, and set `SERVERWATCH_COOKIE_SECURE=true`
once TLS works.

### Caddy

The [Caddy template](../deployments/caddy/Caddyfile) obtains and renews HTTPS
certificates automatically. Replace `serverwatch.example.com` with your public
hostname, then generate a hash for the edge-auth password:

```bash
caddy hash-password
```

Save the result in `/etc/caddy/.env` without quotes:

```dotenv
SERVERWATCH_CADDY_PASSWORD_HASH=<paste the generated hash here>
```

Set that file to mode `0600`, then add this systemd override with
`sudo systemctl edit caddy`:

```ini
[Service]
EnvironmentFile=/etc/caddy/.env
```

Install and validate the template before reloading Caddy:

```bash
sudo cp deployments/caddy/Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile --envfile /etc/caddy/.env
sudo systemctl daemon-reload
sudo systemctl reload caddy
```

The Caddy edge-auth username is `serverwatch`. `/health`, `/ready`, `/status`,
and `/status.css` stay public; the dashboard and `/api` require edge auth.
`/metrics` is always denied by this public virtual host. Set
`SERVERWATCH_COOKIE_SECURE=true` after HTTPS is working.

## Upgrading

1. Stop the service: `sudo systemctl stop serverwatch`.
2. Back up first: `scripts/backup.sh`.
3. Replace the contents of `/opt/serverwatch` (keep your `serverwatch.env`).
4. Start the service; migrations apply on startup.

## Verifying a release

```bash
sha256sum -c SHA256SUMS
```
