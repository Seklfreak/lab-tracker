# Manual testing reference

There is **no automated test suite** yet. This doc captures the manual checks
used during development so they can be re-run quickly (and eventually codified —
see "Worth codifying" at the bottom). Commands are copy-paste runnable from the
repo root on macOS.

## Prerequisites

```bash
# infra (Postgres + MinIO, creates the lab-results bucket)
docker compose up -d

# backend (runs migrations on boot, listens on :8080).
# Reads ../.env — needs a real ANTHROPIC_API_KEY for extraction tests.
(cd backend && go run ./cmd/server)
```

Most recipes assume a profile exists. Helpers used throughout:

```bash
PID=$(curl -s localhost:8080/api/profiles | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
analyte_id() { curl -s localhost:8080/api/analytes | tr '}' '\n' | grep "\"name\":\"$1\"" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'; }
```

Restart the backend after backend code changes (it holds :8080):

```bash
lsof -ti tcp:8080 | xargs kill -9 2>/dev/null; sleep 1
(cd backend && go run ./cmd/server > /tmp/labtracker-server.log 2>&1 &)
until grep -qE "listening|level=ERROR" /tmp/labtracker-server.log; do sleep 1; done
```

## Build / type-check (the cheapest regression gate)

```bash
(cd backend && go build ./... && go vet ./...)
(cd frontend && npm run build)   # tsc type-check + vite build
```

After editing SQL queries or migrations, regenerate sqlc and rebuild:

```bash
(cd backend && go run github.com/sqlc-dev/sqlc/cmd/sqlc@latest generate && go build ./...)
```

## Generating test lab PDFs

`cupsfilter` (ships with macOS) turns a text file into a PDF the extractor can read:

```bash
cat > /tmp/lab.txt <<'EOF'
Quest Diagnostics   Collected: 06/07/2025  Reported: 06/09/2025

COMPREHENSIVE METABOLIC PANEL
Test              Result   Flag  Units    Reference Range
GLUCOSE           91             mg/dL    65-99
SODIUM            140            mmol/L   135-146

URINALYSIS, ROUTINE
GLUCOSE           NEGATIVE
PROTEIN           NEGATIVE
EOF
cupsfilter /tmp/lab.txt > /tmp/lab.pdf 2>/dev/null
```

## 1. Smoke test (no LLM key needed)

Exercises health, profiles, the seeded analytes, upload→MinIO, and the
confirm/save path (which doesn't need extraction).

```bash
curl -s localhost:8080/health                                  # {"status":"ok"}
curl -s -X POST localhost:8080/api/profiles -H 'Content-Type: application/json' -d '{"name":"Test"}'
curl -s localhost:8080/api/analytes | grep -o '"id"' | wc -l   # seeded analyte count (>70)

# upload stores to MinIO and creates a report in status=parsing
PID=$(curl -s localhost:8080/api/profiles | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
RID=$(curl -s -X POST "localhost:8080/api/profiles/$PID/reports" -F "file=@/tmp/lab.pdf" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

# confirm/save a result, then read it back
GLU=$(analyte_id Glucose)
curl -s -X POST "localhost:8080/api/reports/$RID/confirm" -H 'Content-Type: application/json' -d '{
  "sourceLab":"Quest","collectedDate":"2026-01-15","reportedDate":null,
  "results":[{"analyteId":"'"$GLU"'","rawTestName":"Glucose, Serum","valueText":"95","valueNumeric":95,"unit":"mg/dL","referenceLow":70,"referenceHigh":99,"referenceText":"70-99","observedDate":null,"learnAlias":true}]
}'
curl -s "localhost:8080/api/profiles/$PID/results"                       # dashboard (latest per analyte, w/ count + isFavorite)
curl -s "localhost:8080/api/profiles/$PID/results?analyte_id=$GLU"       # trend
curl -s -o /tmp/dl.pdf -w "%{http_code} %{content_type}\n" "localhost:8080/api/reports/$RID/pdf"  # 200 application/pdf
```

## 2. Analyte matching coverage (DB-only, no LLM)

This is the logic most often broken by seed/query changes. Paste a report's
printed test names and confirm each resolves to a canonical analyte. `psql`
mirrors what `enrichDraft` does (case-insensitive alias-then-name match).

```bash
docker compose exec -T postgres psql -U labtracker -d labtracker <<'SQL'
WITH printed(name) AS (VALUES
  ('GLUCOSE'),('CHOLESTEROL, TOTAL'),('HDL CHOLESTEROL'),('LDL-CHOLESTEROL'),
  ('UREA NITROGEN (BUN)'),('EGFR'),('MCV'),('ABSOLUTE NEUTROPHILS'),
  ('HEPATITIS A AB, TOTAL'),('CHLAMYDIA TRACHOMATIS RNA, TMA, UROGENITAL'),
  ('MEASLES AB (IGG), IMMUNE STATUS')
)
SELECT p.name AS printed, COALESCE(a_alias.name, a_name.name, '*** NEW ***') AS matched
FROM printed p
LEFT JOIN analyte_aliases al ON lower(btrim(al.raw_name)) = lower(btrim(p.name))
LEFT JOIN analytes a_alias ON a_alias.id = al.analyte_id
LEFT JOIN analytes a_name ON lower(btrim(a_name.name)) = lower(btrim(p.name))
ORDER BY (COALESCE(a_alias.name, a_name.name) IS NULL) DESC, p.name;
SQL
```

Expectation: no row shows `*** NEW ***` for a test that should be seeded.

## 3. Specimen-aware matching (the urine/serum collision)

Needs a real `ANTHROPIC_API_KEY`. Build a PDF with both a serum and a urine
Glucose plus a specimen-neutral urine NAAT, and confirm the suggestions:

```bash
cat > /tmp/lab3.txt <<'EOF'
Quest Diagnostics   Collected: 06/07/2025  Reported: 06/09/2025
COMPREHENSIVE METABOLIC PANEL
GLUCOSE           91        mg/dL    65-99
URINALYSIS, ROUTINE
GLUCOSE           NEGATIVE
INFECTIOUS DISEASE (urine specimen)
CHLAMYDIA TRACHOMATIS RNA, TMA, UROGENITAL      NOT DETECTED
EOF
cupsfilter /tmp/lab3.txt > /tmp/lab3.pdf 2>/dev/null

PID=$(curl -s localhost:8080/api/profiles | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
RID=$(curl -s -X POST "localhost:8080/api/profiles/$PID/reports" -F "file=@/tmp/lab3.pdf" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
for i in $(seq 1 45); do ST=$(curl -s "localhost:8080/api/reports/$RID" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'); [ "$ST" != "parsing" ] && break; sleep 2; done
curl -s "localhost:8080/api/reports/$RID" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['draft']['results']:
    print(f\"  {r['testName'][:30]:<32} specimen={str(r['specimen']):<7} -> {r['suggestedAnalyteName'] or '(new)'}\")"
```

Expected: serum `GLUCOSE` → **Glucose**, urine `GLUCOSE` → **Urine Glucose**,
urine `CHLAMYDIA …` → **Chlamydia trachomatis RNA** (specimen-neutral fallback).

## 4. Qualitative reference + per-result notes (LLM)

A PDF with qualitative results and an interpretive comment should populate
`referenceRange` and `note`:

```bash
cat > /tmp/lab4.txt <<'EOF'
Quest Diagnostics   Collected: 06/07/2025  Reported: 06/09/2025
HEPATITIS C ANTIBODY              NON-REACTIVE     Non-Reactive
RPR (DX) W/REFL TITER AND CONFIRMATORY TESTING   NON-REACTIVE   Reference Range: NON-REACTIVE
   No laboratory evidence of syphilis. If recent exposure is suspected, submit a new sample in 2-4 weeks.
EOF
cupsfilter /tmp/lab4.txt > /tmp/lab4.pdf 2>/dev/null
# upload + poll as above, then check draft results have referenceRange and note populated.
```

## 5. Favorites

```bash
PID=$(curl -s localhost:8080/api/profiles | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -1)
GLU=$(analyte_id Glucose)
curl -s -o /dev/null -w "%{http_code}\n" -X POST "localhost:8080/api/profiles/$PID/favorites" -H 'Content-Type: application/json' -d "{\"analyteId\":\"$GLU\"}"   # 204
curl -s "localhost:8080/api/profiles/$PID/results" | python3 -c "import json,sys;[print(r['analyteName'],r['isFavorite']) for r in json.load(sys.stdin)]"
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE "localhost:8080/api/profiles/$PID/favorites/$GLU"  # 204
```

## 6. Report management (reparse / delete)

```bash
RID=...   # an existing report id
curl -s -o /dev/null -w "reparse %{http_code}\n" -X POST "localhost:8080/api/reports/$RID/reparse"   # 202
curl -s -o /dev/null -w "delete %{http_code}\n" -X DELETE "localhost:8080/api/reports/$RID"          # 204
curl -s -o /dev/null -w "get %{http_code}\n" "localhost:8080/api/reports/$RID"                        # 404
```

## 7. Migrations / schema spot-checks

```bash
# a column exists / was dropped
docker compose exec -T postgres psql -U labtracker -d labtracker -tAc \
  "SELECT count(*) FROM information_schema.columns WHERE table_name='lab_results' AND column_name='note';"

# specimen tagging coverage (expect 0 untagged)
docker compose exec -T postgres psql -U labtracker -d labtracker -tAc \
  "SELECT count(*) FROM analytes WHERE specimens IS NULL;"
```

## Frontend checks (manual, in the browser)

`cd frontend && npm run dev` → http://localhost:5173. Sanity flow:

1. Theme follows OS light/dark; flip macOS appearance and the chart recolors.
2. Upload a PDF → parsing spinner → review form pre-filled with analyte
   suggestions (specimen shown under each test name; combobox is searchable and
   not clipped by the scrolling table).
3. Qualitative rows show an editable **Note** sub-row; **Reference** column holds
   the qualitative expected value.
4. Save → Dashboard shows the analyte (favorites pinned on top, reading count per
   card, H/L/Abnormal flag derived from value vs reference).
5. Analyte detail → trend chart shades green (in range) / red (out of range),
   note shown italic under a reading, per-point PDF links.
6. Reports → Review / Retry / Delete actions on each row.

## Worth codifying (when we add a real suite)

- **Go pure-logic unit tests** (no DB): `llm.extractJSONObject`, the pgtype
  conversion helpers in `internal/api/helpers.go`, `ptrToDate`.
- **Go DB/integration tests** (Postgres via testcontainers or a CI `DATABASE_URL`):
  run migrations, then assert §2/§3 matching and the confirm→alias-learning path.
  This is where real regressions hide.
- **Frontend unit tests** (Vitest): `src/lib/format.ts` (`statusTone`,
  `derivedFlag`, `referenceLabel`) and the chart Y-domain math in `AnalyteDetail`.
- **Seed-coverage test**: assert the printed names from real reports all resolve
  (§2 as an automated assertion).
