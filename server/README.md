# DiaryAI Server

Go-сервер синхронизации зашифрованного дневника. Сервер хранит **только зашифрованные блобы** и не видит содержимого записей.

## Стек

- Go 1.23
- PostgreSQL 16
- chi (роутер), pgx (драйвер БД), JWT (HS256), bcrypt (для auth_key)

## Структура

```
cmd/diary/         entry-point
internal/
  config/          загрузка env
  db/              pgx pool
  httpx/           helpers (JSON, ошибки)
  auth/            register, login, login/verify, JWT middleware
  sync/            push, pull зашифрованных записей
migrations/        SQL-миграции (golang-migrate)
```

## Быстрый старт

### Вариант 1: всё в Docker (рекомендуется)

```bash
cp .env.example .env       # отредактируй DIARY_JWT_SECRET
make up                    # postgres + миграции + сервер
make logs                  # логи сервера
curl http://localhost:8080/healthz
```

`make up` поднимает Postgres, прогоняет миграции и стартует сервер. Образ собирается из [Dockerfile](Dockerfile) (multi-stage, distroless, ~15 МБ).

```bash
make down                  # остановить всё
make rebuild               # пересобрать образ сервера и перезапустить
```

### Вариант 2: сервер локально, Postgres в Docker

```bash
make db-up                                      # только postgres
cp .env.example .env
make deps
export DIARY_DATABASE_URL="postgres://diary:diary_dev_password@localhost:5432/diary?sslmode=disable"
make migrate-up-local                           # нужен golang-migrate в PATH
make run
```

## Эндпоинты

### Auth

| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/auth/register` | Регистрация. Body: `{login, auth_key, kdf_salt, kdf_params}`. Всё base64. |
| POST | `/auth/login` | Получить соль и параметры KDF для логина. Body: `{login}`. |
| POST | `/auth/login/verify` | Подтвердить auth_key, получить JWT. Body: `{login, auth_key}`. |

### Sync (требует `Authorization: Bearer <jwt>`)

| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/sync/push` | Залить пачку зашифрованных записей (LWW по `updated_at`). |
| GET | `/sync/pull?since=<rfc3339>` | Скачать изменения с указанного момента. |

### Health

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/healthz` | Health check |

## Принципы безопасности

1. **Сервер не знает пароля.** Клиент локально через Argon2id из `(login, password)` выводит:
   - `master_key` — остаётся на устройстве, шифрует записи (XChaCha20-Poly1305).
   - `auth_key` — отправляется на сервер вместо пароля.
2. Сервер хранит `bcrypt(auth_key)`. Из него нельзя восстановить `master_key` или пароль.
3. Записи хранятся в `entries.ciphertext` зашифрованными. Сервер не знает ни текста, ни категорий.
4. Чтобы не давать перечислять логины, `/auth/login` для несуществующих логинов возвращает детерминированную псевдо-соль (одинаковую при повторных запросах).

## ИИ и транскрипция

Бесплатно для всех пользователей (через наш ключ OpenRouter/Groq), с rate-лимитом по таблице `ai_usage`. Записи и аудио расшифровываются на клиенте и отправляются нашему прокси, который добавляет API-ключ и пересылает провайдеру. Мы не логируем содержимое.

Продвинутые пользователи могут в настройках клиента указать **свой ключ** OpenRouter или RouterAI.ru — тогда запросы идут напрямую от клиента к провайдеру, минуя наш сервер. Ключ хранится только локально (Keychain/Keystore).

## TODO

- [ ] AI-прокси (`/ai/analyze`) → OpenRouter (с rate-лимитом по `ai_usage`)
- [ ] Транскрипция (`/transcribe`) → Groq Whisper (с rate-лимитом)
- [ ] Тесты
- [ ] Logging-фильтр: гарантировать что тело AI/transcribe запросов не попадает в логи
