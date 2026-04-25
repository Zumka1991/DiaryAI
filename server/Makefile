.PHONY: deps run build test fmt \
        db-up db-down up down logs rebuild \
        migrate-up migrate-down migrate-up-local migrate-down-local

# --- локальная разработка (Go на хосте) ---
deps:
	go mod tidy

run:
	go run ./cmd/diary

build:
	go build -o diary ./cmd/diary

test:
	go test ./...

fmt:
	go fmt ./...

# Только Postgres в докере, сервер — локально
db-up:
	docker compose up -d postgres

db-down:
	docker compose stop postgres

# Миграции с хоста (требует golang-migrate в PATH)
migrate-up-local:
	migrate -path ./migrations -database "$$DIARY_DATABASE_URL" up

migrate-down-local:
	migrate -path ./migrations -database "$$DIARY_DATABASE_URL" down 1

# --- полный стек в докере ---
up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f server

rebuild:
	docker compose build --no-cache server && docker compose up -d server

# Прогнать миграции через контейнер (миграции уже запускаются автоматически в `up`,
# это команда для ручного повторного прогона).
migrate-up:
	docker compose run --rm migrate

migrate-down:
	docker compose run --rm migrate -path=/migrations \
		-database=postgres://diary:diary_dev_password@postgres:5432/diary?sslmode=disable down 1
