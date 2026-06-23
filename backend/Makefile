.PHONY: sqlc run build tidy migrate-down

sqlc:
	go run github.com/sqlc-dev/sqlc/cmd/sqlc@latest generate

tidy:
	go mod tidy

build:
	go build -o bin/server ./cmd/server

run:
	go run ./cmd/server

# Roll back all migrations (requires DATABASE_URL). Useful in dev.
migrate-down:
	go run github.com/golang-migrate/migrate/v4/cmd/migrate@latest \
		-path internal/db/migrations \
		-database "$(DATABASE_URL)" down
