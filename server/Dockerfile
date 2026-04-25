# syntax=docker/dockerfile:1.7

# --- builder ---
FROM golang:1.23-alpine AS builder

WORKDIR /src

# Кэшируем зависимости отдельным слоем.
# go.sum может отсутствовать на свежем чекауте — сгенерим через `go mod tidy`.
COPY go.mod go.sum* ./
RUN go mod download || true

COPY . .

# Генерим go.sum (если отсутствует) и собираем статический бинарник.
# Объединено в один RUN, чтобы Docker не закешировал tidy отдельно от build.
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build \
        -ldflags="-s -w" \
        -o /out/diary \
        ./cmd/diary

# --- runtime ---
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=builder /out/diary /app/diary

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/app/diary"]
