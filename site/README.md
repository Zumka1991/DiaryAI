# DiaryAI Site

Статичный лендинг для diaryai.ru. Один HTML + один CSS, без билда.

## Локальный запуск (без Docker)

Просто открой `index.html` в браузере. Всё.

## В Docker (как в проде)

```bash
cd site
docker compose up -d --build
```

Откроется на `http://localhost:8091`.

## Структура

```
site/
  index.html         главная страница (hero + features + download + trust)
  styles.css         все стили
  Dockerfile         nginx-alpine
  nginx.conf         gzip, кэш, security headers
  docker-compose.yml
```

## Что меняется в проде

1. На VPS поднять Caddy перед всеми сервисами (api + site) — он сам выдаст TLS-сертификаты Let's Encrypt:

   ```caddyfile
   diaryai.ru {
       reverse_proxy localhost:8091
   }

   api.diaryai.ru {
       reverse_proxy localhost:8090
   }
   ```

2. Заменить ссылки `https://github.com/` в `index.html` на реальный репозиторий.
3. Когда соберём релизные APK/EXE — поставить прямые ссылки в `download-card`.
