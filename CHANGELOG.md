# Changelog

Breaking changes come first in each entry. Read the entry before applying a Railway "update available" notice.

## 1.8.0 (2026-11-21)

- First release: Shiori 1.8.0 (`ghcr.io/go-shiori/shiori:alpine-v1.8.0`, pinned by digest) with Railway Postgres.
- The start script replaces Shiori's built-in `shiori` / `gopher` owner account with `SHIORI_ADMIN_USERNAME` / a generated `SHIORI_ADMIN_PASSWORD` before the public port opens.
- README: Deploy on Railway button for the published template `shiori-2`.
- Health check `GET /system/liveness`; data on a volume at `/shiori`; unexpected stops exit non-zero so Railway restarts the service.
