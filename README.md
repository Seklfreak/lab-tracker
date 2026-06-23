# Lab Tracker

Self-hosted app to consolidate lab results (Quest, hospital, etc.) into one place,
visualized over time, with separate profiles. Upload a PDF → Claude scans it →
review/edit the parsed results → save dated values → graph trends.

No authentication (yet). Personal-scale.

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
`lab_reports` (one PDF), `lab_results` (one dated measurement — the graph unit).
See `backend/internal/db/migrations`.

## Not yet implemented

- Authentication.
- Unit normalization across labs (mg/dL ↔ mmol/L).
- Containerized deployment (homelab k3s).
