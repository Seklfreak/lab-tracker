# Lab Tracker

Self-hosted app to consolidate lab results (Quest, hospital, etc.) into one place,
visualized over time, with separate profiles. Upload a PDF → Claude scans it →
review/edit the parsed results → save dated values → graph trends.

Personal-scale. Authenticates via OIDC (any OpenID Connect provider, e.g.
Authentik) — the API validates Bearer JWTs and the SPA does Authorization Code +
PKCE; set `AUTH_DISABLED=true` to run locally without it.

## Stack

- **Backend:** Go, chi, Postgres (pgx + sqlc), golang-migrate, MinIO (S3), Anthropic SDK (`claude-opus-4-8`).
- **Frontend:** React + TypeScript + Vite, Tailwind, Recharts, TanStack Query, React Router.
- **Infra (dev):** Postgres + MinIO via Docker Compose.

## How it works

1. Upload a PDF → stored in MinIO, a `lab_reports` row is created with `status='parsing'`.
2. A background goroutine sends the PDF to Claude and gets back structured JSON;
   each parsed test name is matched to a canonical **analyte** via the alias table.
   Status flips to `parsed`.
3. The frontend polls the report, then shows a review form pre-filled with the
   extracted values + suggested analyte mappings.
4. On save, results are written to `lab_results` and any newly-mapped names are
   learned as aliases, so the same test from a different lab auto-maps next time.

## Prerequisites

- Go 1.26+
- Node 18+
- Docker (for Postgres + MinIO)
- An Anthropic API key

## Setup

```bash
cp .env.example .env
# edit .env and set ANTHROPIC_API_KEY

# start Postgres + MinIO (creates the lab-results bucket)
docker compose up -d
```

### Backend

```bash
cd backend
go run ./cmd/server        # runs migrations on boot, listens on :8080
```

Env is read from `../.env` (or `./.env`). Required: `DATABASE_URL`,
`ANTHROPIC_API_KEY`, `MINIO_ENDPOINT`. See `.env.example`.

Regenerate sqlc after changing queries/migrations:

```bash
make sqlc
```

### Frontend

```bash
cd frontend
npm install
npm run dev                # http://localhost:5173 (proxies /api to :8080)
```

## Usage

1. Open http://localhost:5173, add a profile (top-right).
2. **Upload** → choose a lab PDF → wait for parsing → review the form → **Save**.
3. **Dashboard** shows the latest value per analyte, grouped by category.
4. Click an analyte to see its trend over time with the reference band, and links
   to each source PDF.

## API

| Method | Path | Purpose |
|---|---|---|
| GET/POST | `/api/profiles` | list / create profiles |
| DELETE | `/api/profiles/{id}` | delete profile |
| POST | `/api/profiles/{id}/reports` | upload a PDF (multipart `file`) |
| GET | `/api/profiles/{id}/reports` | list reports |
| GET | `/api/profiles/{id}/results` | latest result per analyte (`?analyte_id=` for a trend) |
| GET | `/api/profiles/{id}/analytes` | analytes that have data |
| GET | `/api/reports/{id}` | report status + parsed draft (polled) |
| POST | `/api/reports/{id}/confirm` | save edited results + learn aliases |
| GET | `/api/reports/{id}/pdf` | stream the original PDF |
| GET | `/api/analytes` | canonical analyte list |

## Data model

`profiles`, `analytes` (canonical tests), `analyte_aliases` (raw name → analyte),
`lab_reports` (one PDF), `lab_results` (one dated measurement — the graph unit),
`favorites` (per-profile pinned analytes). See `backend/internal/db/migrations`.

## Testing

Unit tests cover the pure logic:

```bash
(cd backend && go test ./...)   # JSON extraction, pgtype conversions, dates
(cd frontend && npm test)       # statusTone, derivedFlag, referenceLabel, chartYDomain
```

DB/integration and extraction paths are still verified manually — recipes
(smoke test, analyte matching, specimen disambiguation, favorites, report
management, etc.) are in [`docs/manual-testing.md`](docs/manual-testing.md).

## Releases

Container images are versioned with semver. Releases are **cut automatically**: every
commit on `main` that passes the Test workflow is released — `release.yaml` asks Claude
(Haiku) to pick the bump (major/minor/patch) and write release notes from the commits
since the last tag, then tags the new version, publishes a GitHub Release with those
notes, and builds `backend`/`frontend`/`mcp` images tagged `X.Y.Z` + `X.Y` + `latest`
for that exact commit. Claude may also decide a commit needs **no release** (docs/markdown
or CI-only changes), in which case nothing is tagged. (No API key → it falls back to a
patch bump, or skips when only non-shipping paths changed.) The homelab deploys pin an
explicit version (not `latest`), so what's running is always reproducible.

- **Minor / major release:** tag it yourself — `git tag v0.2.0 && git push origin v0.2.0`.
  The auto-bumper continues from the highest tag (next auto release would be `v0.2.1`).
- **Deploy a release** (homelab repo): bump the image tag on the `lab-tracker` deployments
  (`apps/lab-tracker/lab-tracker.yaml` api+web, `apps/mcp/lab-tracker-mcp.yaml` mcp) and
  commit — Flux rolls it out. **Roll back** by pointing those tags at a prior version.

## Not yet implemented

- Unit normalization across labs (mg/dL ↔ mmol/L).
- Per-user data isolation (today any authenticated user shares all profiles).

Future ideas (MCP server, iOS app, broader health record) are in
[`docs/roadmap.md`](docs/roadmap.md).
