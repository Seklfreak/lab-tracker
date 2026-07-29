# CLAUDE.md

Guidance for working in this repo. Read before making changes.

## Keep the docs in sync

When a change affects behavior, features, endpoints, the data model, config, or
setup, update the docs in the **same change**:

- **`README.md`** — user/dev-facing: intro, prerequisites, the API table, the
  data-model summary, env vars, testing commands.
- **`docs/roadmap.md`** — move items to **Done** (with a date) when shipped; add
  new ideas under the appropriate heading. Don't restate roadmap detail in the
  README — link to it.

If a change makes a doc wrong, fixing the doc is part of the change, not a
follow-up.

## Layout

- `backend/` — Go (chi, pgx + sqlc, golang-migrate, MinIO, Anthropic SDK).
  - `cmd/server` — the REST API. `cmd/mcp` — the MCP connector (Streamable HTTP).
  - `internal/db/migrations` — SQL migrations; `internal/db/queries` — sqlc input;
    `internal/db/sqlc` — generated (do **not** hand-edit).
- `frontend/` — React 19 + TypeScript + Vite + Tailwind + TanStack Query.

## Toolchain

- **Node 20.19+ required** (Vite 8 / ESLint). The machine's default `node` may be
  18, which silently fails or produces confusing errors — use nvm/mise to get 20+
  for `npm` commands (`dev`, `build`, `lint`, `test`).
- **Go 1.26+.**

## Database / sqlc

- After editing `internal/db/queries/*.sql` or adding a migration, regenerate with
  `make sqlc` (pinned to a fixed sqlc version in the Makefile). Never edit
  `internal/db/sqlc/*` by hand.
- Migrations are embedded and run on server boot. Add paired
  `NNN_name.up.sql` / `NNN_name.down.sql`.

## Auth & access model (important)

The API is per-user. Every signed-in user sees only profiles they **own or that
are shared with them**.

- Scope all profile/result/report queries through `GetProfileForUser` /
  `ListProfilesForUser`. Endpoints keyed on a report/result id (no profile in the
  URL) must resolve the owning profile and access-check it — return 404 (not 403)
  so existence isn't leaked.
- The auth middleware upserts a `users` row from the JWT and puts the user id +
  `isAdmin` in the request context (`AUTH_DISABLED` → fixed dev user, treated as
  admin). Admin endpoints gate on `isAdmin` (the `ADMIN_EMAILS` allowlist).
- When adding any endpoint that touches user data, scope it the same way and add
  an isolation test (user A must not reach user B's data).

## Frontend conventions

- Modals/overlays must render through a **portal to `document.body`**
  (`createPortal`). The app header uses `backdrop-blur`, which creates a
  containing block for `position: fixed` descendants — a `fixed inset-0` overlay
  rendered inside the header is sized to the header, not the viewport.
- Obey the Rules of Hooks. `npm run lint` (ESLint + `react-hooks`) catches
  hook-order bugs that `tsc` and `vite build` do **not** (e.g. a hook after an
  early `return` → blank page). Lint runs in CI.

## Before committing

- Backend: `cd backend && golangci-lint run ./... && go build ./... && go test ./...`
  (golangci-lint config in `backend/.golangci.yml`; it includes govet)
- Frontend: `cd frontend && npm run lint && npx tsc --noEmit && npm test`
- Go imports follow goimports grouping with the local module
  (`github.com/Seklfreak/lab-tracker/...`) last. `gofmt -l` flags this, but it's
  the repo convention — don't reformat to "fix" it.
- Handler tests use `sqlctest.FakeQuerier` (set only the `*Fn` fields a test
  needs; unset methods panic).

## CI

`.github/workflows/test.yaml` runs `go test` and the frontend
`lint` + `build` + `test` on every push/PR. Green `main` auto-cuts a versioned
release. Keep both jobs green.
