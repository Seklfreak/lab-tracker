#!/usr/bin/env bash
# Smoke test for the release images, run by the `image` job in test.yaml:
#
#   scripts/image-smoke.sh lab-tracker-backend:ci lab-tracker-mcp:ci
#
# Each image is distroless plus a Go binary built on the runner. Renovate
# auto-merges base-image and Go bumps once Test is green, and nothing else ever
# starts the images. This does, against a throwaway Postgres and S3 store: the
# backend runs its migrations, creates its bucket and answers API calls with
# the database, and the MCP server answers an MCP initialize.
set -euo pipefail

backend=${1:?usage: $0 <backend-image> <mcp-image>}
mcp=${2:?usage: $0 <backend-image> <mcp-image>}
net=lab-tracker-smoke
db="postgres://postgres:smoke@lt-smoke-pg:5432/labtracker?sslmode=disable"
cleanup() {
  docker rm -f lt-smoke-backend lt-smoke-mcp lt-smoke-pg lt-smoke-s3 >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

fail() {
  echo "FAIL $*"
  for c in lt-smoke-backend lt-smoke-mcp; do
    echo "--- $c"
    docker logs "$c" 2>&1 | tail -15
  done
  exit 1
}

# wait_for <url>: poll until it answers 2xx, up to 30 s.
wait_for() {
  for _ in $(seq 150); do
    curl -fsS "$1" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

docker network create "$net" >/dev/null
docker pull -q postgres:18-alpine >/dev/null
docker pull -q chrislusf/seaweedfs:4.48 >/dev/null
docker run -d --name lt-smoke-pg --network "$net" \
  -e POSTGRES_PASSWORD=smoke -e POSTGRES_DB=labtracker postgres:18-alpine >/dev/null
# Any S3-compatible store will do; SeaweedFS's gateway accepts any credentials
# when no identities are configured.
docker run -d --name lt-smoke-s3 --network "$net" chrislusf/seaweedfs:4.48 server -s3 >/dev/null
for _ in $(seq 60); do
  docker exec lt-smoke-pg pg_isready -q -U postgres -d labtracker 2>/dev/null && break
  sleep 0.5
done

docker run -d --name lt-smoke-backend --network "$net" -p 18080:8080 \
  -e DATABASE_URL="$db" -e ANTHROPIC_API_KEY=smoke -e AUTH_DISABLED=true \
  -e MINIO_ENDPOINT=lt-smoke-s3:8333 -e MINIO_ACCESS_KEY=smoke -e MINIO_SECRET_KEY=smoke-secret \
  -e MINIO_USE_SSL=false \
  "$backend" >/dev/null
# The S3 gateway takes a few seconds to come up; the backend exits if the
# bucket check fails, so give it a retry rather than a fixed sleep.
if ! wait_for http://localhost:18080/health; then
  docker start lt-smoke-backend >/dev/null 2>&1 || true
  wait_for http://localhost:18080/health || fail "backend /health never answered"
fi
echo "ok   backend /health (migrations ran, bucket ready)"

for path in /api/me /api/profiles; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:18080$path")
  [ "$code" = 200 ] || fail "backend GET $path = $code"
done
echo "ok   backend /api/me and /api/profiles read the database"

docker run -d --name lt-smoke-mcp --network "$net" -p 18081:8080 \
  -e DATABASE_URL="$db" -e ANTHROPIC_API_KEY=smoke \
  "$mcp" >/dev/null
wait_for http://localhost:18081/health || fail "mcp /health never answered"
init=$(curl -sS -X POST http://localhost:18081/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}')
grep -q '"serverInfo"' <<<"$init" || fail "mcp initialize: $init"
echo "ok   mcp /health and initialize"

for c in lt-smoke-backend lt-smoke-mcp; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c")" = true ] || fail "$c exited"
done
echo "image smoke test passed"
