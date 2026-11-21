# Shiori on Railway

One-click Railway template for [Shiori](https://github.com/go-shiori/shiori), the simple open-source (MIT) bookmark manager written in Go. Shiori saves the links you keep, fetches a readable copy of each page and can store a full offline archive, so your reading list survives link rot.

**Version:** Shiori **1.8.0**, the official Alpine image `ghcr.io/go-shiori/shiori:alpine-v1.8.0@sha256:79ca8588c0abc5cc1ccad11ce5ab7f9bab393966b699d60be9c82aa6b356fd3a` (multi-arch index digest), pinned in this repo's [`Dockerfile`](Dockerfile).

## What the template deploys

Two services, wired over Railway's private network:

| Service | Source | What it does |
|---|---|---|
| **Shiori** | this repo (`Dockerfile`, `start.sh`) | Web UI, REST API and browser-extension endpoint on Railway's `PORT` (8080), behind a public HTTPS domain. A volume at `/shiori` keeps page archives, thumbnails and ebooks. Health check: `GET /system/liveness` (no login). |
| **Postgres** | Railway's PostgreSQL | Bookmarks, tags and accounts, on its own volume. |

The start script:

- converts Railway's `postgresql://` URL to the `postgres://` form Shiori accepts (Shiori rejects `postgresql://`) and adds `sslmode=disable` for the private network;
- waits for Postgres to accept connections, so the first deploy works even when Postgres is still starting;
- **removes Shiori's built-in `shiori` / `gopher` account.** Upstream Shiori creates that owner account on every empty database. Before the public port opens, the script renames it to `SHIORI_ADMIN_USERNAME` and sets `SHIORI_ADMIN_PASSWORD` (generated at deploy), then checks that `shiori` / `gopher` no longer logs in. If it can't, the service refuses to start;
- execs Shiori as the main process, so a crash or out-of-memory kill exits non-zero and Railway's `ON_FAILURE` restart policy brings it back on every plan.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `SHIORI_ADMIN_USERNAME` | `admin` | Owner account created on the first start. |
| `SHIORI_ADMIN_PASSWORD` | `${{secret(24)}}` | Password for that account, generated at deploy. Read it in the Shiori service's **Variables** tab. |
| `SHIORI_HTTP_SECRET_KEY` | `${{secret(64)}}` | Signs login sessions; keeps you logged in across restarts. |
| `SHIORI_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection over the private network. |
| `SHIORI_DIR` | `/shiori` | Data directory on the volume. |
| `PORT` | `8080` | Port Shiori listens on. |

The deploy form asks nothing: every value is generated or derived.

`SHIORI_ADMIN_USERNAME` and `SHIORI_ADMIN_PASSWORD` are used once, on the first start. Change the password later in Shiori (gear icon → *My account*); editing the variable afterwards has no effect.

Optional upstream settings (add them in the Variables tab when you need them): `SHIORI_HTTP_ROOT_PATH` to serve under a sub-path, `SHIORI_SSO_PROXY_AUTH_ENABLED` for header-based single sign-on behind a trusted proxy. See [Shiori's configuration docs](https://github.com/go-shiori/shiori/blob/v1.8.0/docs/Configuration.md).

## After deploying

1. Wait until both services are green, then open the Shiori service's public URL.
2. Log in with `SHIORI_ADMIN_USERNAME` and `SHIORI_ADMIN_PASSWORD` from the Shiori service's **Variables** tab.
3. Click **+** to add a bookmark. Tick *Create archive* to keep an offline copy, or turn it on by default under the gear icon → *Bookmarks*.
4. Add more users under the gear icon → *Accounts* (there is no public sign-up). Install the [browser extension](https://github.com/go-shiori/shiori-web-ext) and point it at your Railway URL.

## Resources

Shiori idles at about 20 MB of RAM and fits Railway's Free plan (0.5 GB, 1 vCPU). The image sets `GOMAXPROCS=2` and `GOMEMLIMIT=400MiB` so the Go runtime stays inside small plans.

## Updates

When this repo's `main` changes (for example a new Shiori release), Railway shows deployers an "update available" notice and you choose when to apply it. Read [`CHANGELOG.md`](CHANGELOG.md) first: breaking changes are listed at the top of each entry. Shiori migrates its database schema on start. Your bookmarks (Postgres volume) and archives (Shiori volume) stay across updates, redeploys and restarts; use Railway's volume backups to keep copies.

## Local run

```sh
docker compose -f test/compose.yml -p shiori up -d --build
BASE=http://localhost:8080 SUSER=admin PASS=LocalTestPassw0rd sh test/smoke.sh
```

`test/smoke.sh` checks the health path, that `shiori` / `gopher` is refused, the owner login, adding a bookmark with an archive, and the system info.

## License

Shiori is © its contributors, licensed under the MIT License. This wrapper (Dockerfile, start script, docs) is also MIT.
