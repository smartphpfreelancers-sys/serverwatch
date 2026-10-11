# ServerWatch Community Edition

[![CI](https://github.com/smartphpfreelancers-sys/serverwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/smartphpfreelancers-sys/serverwatch/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/smartphpfreelancers-sys/serverwatch)](https://github.com/smartphpfreelancers-sys/serverwatch/releases)
[![License](https://img.shields.io/github/license/smartphpfreelancers-sys/serverwatch)](LICENSE)
[![Container](https://img.shields.io/badge/container-ghcr.io-2496ED?logo=docker&logoColor=white)](https://github.com/smartphpfreelancers-sys/serverwatch/pkgs/container/serverwatch)
[![Go](https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![React](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=black)](https://react.dev)

ServerWatch is a lightweight, self-hosted uptime monitoring platform for websites, APIs, hosts, DNS, and SSL certificates.

![ServerWatch dashboard](docs/images/dashboard.png)

## Project Status

Community Edition **0.1.0** — first release. The backend, dashboard, alerting, and
operations tooling are ready to self-host; see [CHANGELOG.md](CHANGELOG.md) for
what is included and [docs/ROADMAP.md](docs/ROADMAP.md) for what is planned.

## Quick start

```bash
tar xzf serverwatch-0.1.0-linux-amd64.tar.gz
cd serverwatch-0.1.0-linux-amd64
cp .env.example serverwatch.env    # edit DATABASE_URL and secrets
docker compose --env-file serverwatch.env up -d postgres
./bin/serverwatch
```

Download a prebuilt bundle from
[Releases](https://github.com/smartphpfreelancers-sys/serverwatch/releases), or build from
source with `make build && make web-build`. Full walkthrough:
[docs/INSTALLATION.md](docs/INSTALLATION.md).

## Run with Docker

The container is self-contained: it serves the dashboard, proxies the API, and
runs the monitor scheduler. It only needs a Postgres database.

```bash
# 1. Grab a compose file and an env file
curl -O https://raw.githubusercontent.com/smartphpfreelancers-sys/serverwatch/main/deployments/docker/docker-compose.yml
cp .env.example serverwatch.env        # edit POSTGRES_PASSWORD and any secrets

# 2. Start the whole stack (app + Postgres)
docker compose --env-file serverwatch.env up -d
# open http://localhost:8080
```

The published image is `ghcr.io/smartphpfreelancers-sys/serverwatch` (`:latest`, `:1.2`,
`:1.2.3`, or `:edge` for the tip of `main`). It is a multi-arch manifest for
`linux/amd64` and `linux/arm64`.

Prefer a single `docker run` against your own database?

```bash
docker run -d --name serverwatch -p 8080:80 \
  -e DATABASE_URL="postgres://user:pass@your-db:5432/serverwatch?sslmode=disable" \
  ghcr.io/smartphpfreelancers-sys/serverwatch:latest
```

The backend and migrations run automatically on first start. Secrets are read
from environment variables only - never bake them into the image. See
[deployments/docker/](deployments/docker/) for the compose file, the build
`Dockerfile`, and the container Nginx config.

## Features

Delivered in 0.1.0:

- Central dashboard for multiple monitors
- HTTP/HTTPS uptime monitoring
- SSL certificate expiry monitoring
- TCP port and multi-port monitoring
- Ping/ICMP host reachability monitoring
- DNS record monitoring
- Monitor groups, favorites, maintenance mode, search, filtering, sorting, and
  pagination
- Dashboard health summary, per-monitor history, and ranged analytics
- Email (SMTP) and Telegram alerts
- Optional account authentication and shared API token
- Security headers, rate limiting, audit log, and opt-in Prometheus metrics
- Data retention, backup/restore, and Docker/systemd/Nginx deployment templates
- Opt-in public status page at /status

Planned:

- Server agent and CPU/RAM/disk/load/uptime metrics
- Cron heartbeat monitoring and more check types
- Historical charts, teams and roles, and webhooks

See [docs/ROADMAP.md](docs/ROADMAP.md).

## Architecture

ServerWatch consists of:

- Go backend/API (`server/`)
- React + TypeScript dashboard (`web/`)
- PostgreSQL database
- Optional Go agent (`agent/`) — a placeholder in 0.1.0; host metrics are planned
- Docker Compose, systemd, and Nginx deployment templates

The backend performs all network monitoring. The agent is not required to run
ServerWatch. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository Structure

- `server/` - central ServerWatch backend
- `agent/` - optional monitored-server agent (placeholder in 0.1.0)
- `web/` - React frontend
- `database/` - migrations and database-related files
- `docs/` - project documentation
- `scripts/` - helper/install scripts (backup, restore, release)
- `deployments/` - systemd, Nginx, and Docker deployment templates

## Documentation

- [Installation](docs/INSTALLATION.md) - install a release and serve the dashboard
- [Configuration](docs/CONFIGURATION.md) - every environment variable and feature
- [Architecture](docs/ARCHITECTURE.md) - how monitoring and checks work
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Development](docs/DEVELOPMENT.md)
- [Roadmap](docs/ROADMAP.md)
- [Changelog](CHANGELOG.md)

## Ping monitors

Ping targets are hostnames or IP addresses only (for example `server.example.com`, `192.168.1.1`, or `::1`). Do not include a protocol, path, or port. ServerWatch invokes the system `ping` executable, so Linux/Ubuntu installations need `iputils-ping`:

```sh
sudo apt install iputils-ping
```

The ServerWatch service does not need to run as root. Its systemd service
retains `NoNewPrivileges=true`; configure Linux unprivileged ICMP with
`net.ipv4.ping_group_range` for the local `serverwatch` GID. See the
[Ping monitoring architecture decision](docs/ARCHITECTURE.md#ping-monitoring)
and [Ping troubleshooting](docs/TROUBLESHOOTING.md#ping-monitor-is-down-but-manual-ping-works)
for validation and persistent host configuration.

## Port monitors

Multi-port monitors check several explicitly configured TCP ports on one host.
The target is a hostname or IP address only (for example `server.example.com`,
`192.168.1.10`, or `2001:db8::10`); ports are configured separately, for
example `22, 80, 443`. Every configured port must accept a TCP connection for
the monitor to report `UP`.

This is monitoring, not scanning. ServerWatch never scans ranges, never
discovers ports automatically, and only dials ports the user configured, with a
maximum of 20 ports per monitor. See
[Port monitoring](docs/CONFIGURATION.md#multi-port-monitoring) and
[Port troubleshooting](docs/TROUBLESHOOTING.md#port-monitor-shows-down).

## Monitor groups

Monitor groups are an optional organizational feature. A monitor may belong to
zero or one group, and groups have no effect on scheduling, checking, or
alerting.

Group names are trimmed, must be non-empty, are limited to 100 characters, and
must be unique case-insensitively. Deleting a group never deletes its monitors;
those monitors become ungrouped. The dashboard can filter the visible monitor
list by group, Ungrouped, or All Groups without pausing or changing monitors.

## Monitor search and sorting

The dashboard lets you search the loaded monitor list and reorder it. Search is
client-side and case-insensitive, ignores leading and trailing whitespace, and
matches monitor names and targets. An empty search shows every monitor. Search
composes with the existing group filter: monitors are first limited by the
selected group, then by the search text, and then sorted.

Sorting is also client-side and offers Name A → Z, Name Z → A, Status, Monitor
type, Newest, and Oldest, plus a Default option that preserves the existing
incoming order. Status sorting reuses the dashboard presentation state, so
Disabled ranks after Maintenance, and both rank after the normal monitoring
statuses. Search and sorting only change which monitors are visible and in what
order; they never modify a monitor, change monitoring behavior, or affect
scheduling, checkers, alerting, or maintenance. Selections are not persisted
across a browser reload.

## Dashboard health summary

The dashboard shows a compact health summary above the monitor controls:
Total Monitors, Up, Down, Maintenance, Disabled, and Pending / No Data. The
summary is frontend-only and derived from the monitor list the browser has
already loaded; it adds no endpoint, query, or migration.

Every configured monitor is counted in exactly one bucket. A disabled monitor
is always counted as Disabled, even if it is also in maintenance or its last
result was DOWN. Otherwise a monitor in maintenance is counted as Maintenance,
regardless of its last result. Remaining monitors use their current monitoring
status: Down, Up, or Pending / No Data when no result exists yet. The buckets
partition the monitors, so Up + Down + Maintenance + Disabled + Pending always
equals Total Monitors.

The summary is a global overview: it counts every configured monitor and is not
affected by the Group filter, Search, or Sort controls, which only change the
monitor cards shown below it. The summary cards are informational and are not
clickable. See [Health summary](docs/CONFIGURATION.md#dashboard-health-summary)
and [Health summary troubleshooting](docs/TROUBLESHOOTING.md#dashboard-health-summary).

## Monitor maintenance mode

Maintenance mode is a manual, per-monitor switch for planned work. While it is
active, ServerWatch stops running scheduled checks for that monitor, so no new
scheduled result is written and no DOWN, recovery, or SSL-expiry alert is sent
from scheduled checks. The monitor, its configuration, its group, its check
history, and its alert state are all preserved.

Maintenance mode is independent of the enabled flag. A monitor is normally one
of three states:

- Enabled and normal: scheduled monitoring is active.
- Enabled and in maintenance: configured and enabled, but scheduled monitoring
  is temporarily paused.
- Disabled: administratively turned off.

Exiting maintenance does not run a check immediately and does not fabricate an
UP result or recovery event. The monitor becomes eligible for the scheduler
again, and the first real scheduled check is processed with the existing alert
state. The dashboard shows a distinct `Maintenance` badge and provides
`Enter Maintenance` / `Exit Maintenance` actions with a confirmation. See
[Maintenance mode](docs/CONFIGURATION.md#maintenance-mode) and
[Maintenance troubleshooting](docs/TROUBLESHOOTING.md#maintenance-mode).

## API access token

ServerWatch Community Edition can require a bearer token on its API surface.
This is opt-in and off by default: when `SERVERWATCH_API_TOKEN` is unset, the
API behaves exactly as before, so enabling the feature can never break an
existing installation.

Set `SERVERWATCH_API_TOKEN` (for example `openssl rand -hex 32`) in the
environment file and restart the service. While it is set:

- every `/api/v1/...` request must send `Authorization: Bearer <token>`;
  requests without it receive `401 Unauthorized`;
- the `/health` and `/ready` probes stay open so systemd, Docker, and Nginx
  health checks keep working;
- the dashboard prompts for the token and stores it in the browser only, then
  sends it on every request.

The token is a single shared secret for the whole installation. It is not a
per-user account system. See
[API access token](docs/CONFIGURATION.md#api-access-token) for configuration
and operational details.

## Account authentication

Setting `SERVERWATCH_AUTH_ENABLED=true` turns on single-user account
authentication for the dashboard and API. Like the API token, this is opt-in
and off by default, so an existing open installation is unaffected until the
operator enables it.

- On first visit, ServerWatch asks you to create the administrator account
  (email and password). This first-run setup is only offered while no account
  exists, so it cannot be used to add users or take over an initialized
  deployment.
- After that, visitors must sign in. Sessions are tracked with an HttpOnly
  cookie and can be ended with **Sign out**.
- `/health`, `/ready`, and the sign-in endpoints stay open; every other
  `/api/v1/...` route requires a valid session. The `SERVERWATCH_API_TOKEN`
  bearer token keeps working for scripts and health tooling.

Passwords are stored as PBKDF2-HMAC-SHA256 hashes with a random per-password
salt. This release provides a single administrator account, not per-user roles
or multi-tenant permissions. See
[Account authentication](docs/CONFIGURATION.md#account-authentication).

## Security hardening

Phase 0.50 adds hardening that is on by default plus opt-in features:

- Strict security headers (CSP, `X-Frame-Options: DENY`, `nosniff`, referrer and
  cross-origin policies) on every response; `Strict-Transport-Security` only
  over TLS.
- Per-client API rate limiting (`429` over limit) with edge `limit_req` in the
  Nginx template.
- An audit log of every mutating API call, attributed to the user, the shared
  token, or anonymous.
- An optional Prometheus `/metrics` endpoint
  (`SERVERWATCH_METRICS_ENABLED=true`).
- Ready-to-use `deployments/nginx/` and `deployments/systemd/` templates with
  TLS guidance and service sandboxing.

See [Security hardening](docs/CONFIGURATION.md#security-hardening) for details.

## Data retention

Check history (`monitor_results`) is the fastest-growing table, so a built-in job
keeps it bounded:

```dotenv
SERVERWATCH_RESULT_RETENTION_DAYS=30
```

Once at startup and then daily, it deletes results older than the window while
always keeping the newest result for every monitor (so no monitor's last status
is ever blanked). Set it to `0` to keep history forever. See
[Data retention](docs/CONFIGURATION.md#data-retention) and
[Backup and restore](docs/BACKUP_RESTORE.md) (`scripts/backup.sh`,
`scripts/restore.sh`).

## Alert channels

DOWN, recovery, and SSL-expiry alerts are delivered to every enabled channel.
Email (SMTP) and Telegram can be used independently or together:

```dotenv
SERVERWATCH_ALERT_EMAIL_ENABLED=false
SMTP_HOST=smtp.example.com
SMTP_PORT=587
...

SERVERWATCH_ALERT_TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_CHAT_ID=123456789
```

A failure on one channel does not prevent the others from delivering. See
[Telegram alerts](docs/CONFIGURATION.md#telegram-alerts) and
[SMTP email alerts](docs/CONFIGURATION.md#smtp-email-alerts).

## Building and releasing

```bash
make build        # versioned backend binary -> bin/serverwatch
make test         # Go (server + agent) and TypeScript checks
make check        # full merge gate
make release VERSION=v0.1.0   # dist/serverwatch-v0.1.0-linux-amd64.tar.gz + SHA256SUMS
```

The version in `VERSION` is injected into the backend binary and the dashboard,
so `GET /health` and the dashboard header report the running build. Pushing a
`v*` tag publishes a release bundle via GitHub Actions. See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

A `v*` tag also publishes a multi-arch container image to the GitHub Container
Registry (`ghcr.io/<owner>/serverwatch`). Build the image locally with:

```bash
docker build --build-arg VERSION=0.1.0 -t serverwatch:dev .
```

## Support

ServerWatch Community Edition is Apache-2.0 licensed and free to self-host.
Sponsorship keeps maintenance going and funds new features - it is a donation,
not a license or a support contract. If the project is useful to you, the
Sponsor button on the repository is the best way to help. Funding platforms are
configured in [.github/FUNDING.yml](.github/FUNDING.yml).

If ServerWatch is useful to you, a **⭐ Star** helps others discover it - it is
the single biggest thing you can do to support the project. You can also
[watch the repository](https://github.com/smartphpfreelancers-sys/serverwatch/subscription)
for release notifications, or share it with your team.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and
review expectations, and [SECURITY.md](SECURITY.md) to report a vulnerability.

## License

Apache License 2.0
