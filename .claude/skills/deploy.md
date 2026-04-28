---
name: deploy
description: Deploy DiaryAI — обновить лендинг diaryai.ru и Go-сервер api.diaryai.ru на проде
trigger: When the user asks to deploy/redeploy DiaryAI, the landing site, or the API server
---

# DiaryAI deploy playbook

Прод — один Linux VPS, Caddy на хосте проксирует на докер-контейнеры лендинга и API.
Контейнеры поднимаются через `docker compose` отдельно для `site/` и `server/`.

## Хост

- **IP**: `5.253.59.251`
- **Hostname**: `156607.ip-ptr.tech`
- **SSH**: `ssh -i ~/.ssh/id_ed25519 root@5.253.59.251`
- **Repo path**: `/apps/DiaryAI`
- **Домены**: `diaryai.ru` → `localhost:8091` (site), `api.diaryai.ru` → `localhost:8090` (server). TLS — Caddy automatic.

## TL;DR — раскатить лендинг

```bash
ssh -i ~/.ssh/id_ed25519 root@5.253.59.251 \
  "cd /apps/DiaryAI && git pull --ff-only && cd site && docker compose up -d --build"

# Smoke-test
curl -sI https://diaryai.ru | head -5
curl -s https://diaryai.ru | grep -E "DiaryAi-v|version"
```

## TL;DR — раскатить Go-сервер

```bash
ssh -i ~/.ssh/id_ed25519 root@5.253.59.251 \
  "cd /apps/DiaryAI && git pull --ff-only && cd server && docker compose up -d --build"

curl -sI https://api.diaryai.ru/healthz
```

## Локальные правки на сервере

`/apps/DiaryAI` — это рабочая копия. Иногда там есть локальные правки (`server/docker-compose.yml`,
`site/docker-compose.yml` — env-переменные/секреты для прода). Перед `git pull --ff-only` НЕ
делай `git reset --hard` — снесёшь продовый конфиг.

Если `pull` падает с "Your local changes would be overwritten":

```bash
# Стэшим продовые правки, тянем, возвращаем
git stash push -m pre-deploy
git pull --ff-only
git stash pop
```

После `pop` могут быть конфликты, если в апстриме поменялись те же файлы. В таком случае
вручную мерджи `docker-compose.yml`-ы (всё что трогает API_KEY, OPENROUTER_TOKEN, GROQ_TOKEN —
оставляй из `stash@{0}`).

## Структура

```
/apps/DiaryAI
├── site/             nginx-alpine + статичный лендинг (index.html, styles.css)
│   ├── docker-compose.yml   ports: "8091:80"
│   └── Dockerfile
└── server/           Go API (auth + sync + AI/voice прокси)
    ├── docker-compose.yml   ports: "8090:8080" + postgres
    ├── Dockerfile
    └── migrations/   golang-migrate, накатываются на старте
```

## Гочи

- **Не пуш бинарников в репо.** APK и Windows zip раздаются через GitHub Releases. См. скилл `release`.
- **Caddy сам выдаёт TLS** — не надо certbot/nginx-сертификаты.
- **Postgres контейнер один**, persistent volume `diaryai_pgdata`. Резервная копия — `pg_dump` вручную.
- **Healthcheck сервера**: `GET /healthz` → 200. Если красное — `docker logs diaryai_server -n 200`.
- **Проверка после деплоя лендинга** — обязательно открывать `https://diaryai.ru/`, а не локальный 8091, чтобы убедиться что Caddy подхватил.
