---
name: release
description: Cut a new DiaryAI release — собрать APK arm64 и Windows zip, загрузить на GitHub Release, обновить ссылки на лендинге
trigger: When the user asks to cut/build/publish a release, bump the app version, or update download links on diaryai.ru
---

# DiaryAI release playbook

Flutter-приложение собирается **локально** (Windows-машина с Flutter SDK + Android SDK + JDK).
Бинарники не коммитятся в репо — раздаются через GitHub Releases. Лендинг ссылается на
теги вида `v1.0.X`.

## Версия

`app/pubspec.yaml`:
```yaml
version: 1.0.X+N    # X = публичная версия, N = build-number (для Android)
```

Перед релизом подними оба числа.

## TL;DR — выпустить новую версию

Допустим, выпускаем `v1.0.5`. Делаем всё из корня репо `C:\Users\Zumka1991\Documents\GitReps\DiaryAI`.

```bash
# 1. Бамп версии
sed -i 's/^version: .*/version: 1.0.5+6/' app/pubspec.yaml

# 2. Собрать APK arm64 и Windows release параллельно (в Bash-сессии)
( cd app && flutter build apk --release --target-platform android-arm64 ) &
( cd app && flutter build windows --release ) &
wait

# 3. Сложить артефакты в downloads/ (downloads/ в .gitignore — не коммитятся)
cp app/build/app/outputs/flutter-apk/app-release.apk downloads/DiaryAi-v1.0.5.apk

# Windows zip — через PowerShell, потому что bash не видит C:\…\Release\* литерал в Compress-Archive
powershell -Command "Compress-Archive -Path 'C:\Users\Zumka1991\Documents\GitReps\DiaryAI\app\build\windows\x64\runner\Release\*' -DestinationPath 'C:\Users\Zumka1991\Documents\GitReps\DiaryAI\downloads\DiaryAi-v1.0.5.zip' -Force"

# 4. Обновить ссылки на лендинге
sed -i 's|releases/download/v1\.0\.4/DiaryAi-v1\.0\.4\.zip|releases/download/v1.0.5/DiaryAi-v1.0.5.zip|g; \
        s|releases/download/v1\.0\.4/DiaryAi-v1\.0\.4\.apk|releases/download/v1.0.5/DiaryAi-v1.0.5.apk|g; \
        s|· v1\.0\.4|· v1.0.5|g' site/index.html

# 5. Закоммитить, поставить тег, запушить
git add app/pubspec.yaml site/index.html
git commit -m "v1.0.5 — <фича релиза>"
git tag v1.0.5
git push origin main v1.0.5
```

## GitHub Release через REST API

`gh` CLI на этой машине нет — поэтому через API. Токен лежит в Windows Credential Manager под
`git:https://github.com`, его можно достать через `git credential fill`:

```bash
export GH_TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | awk -F= '/^password=/{print $2}')

# Создать релиз
python -c "
import json, urllib.request, os
body = '<release notes — что нового>'
data = json.dumps({'tag_name':'v1.0.5','name':'v1.0.5 — <заголовок>','body':body}).encode('utf-8')
req = urllib.request.Request('https://api.github.com/repos/Zumka1991/DiaryAI/releases',
    data=data, method='POST',
    headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],
             'Accept':'application/vnd.github+json',
             'Content-Type':'application/json'})
j = json.loads(urllib.request.urlopen(req).read().decode('utf-8'))
print('release_id', j['id'])
print('upload_url', j['upload_url'].split('{')[0])
"
# Запоминаем upload_url из вывода

# Загрузить артефакты (UPLOAD_URL = тот, что вернул создатель)
UPLOAD_URL="https://uploads.github.com/repos/Zumka1991/DiaryAI/releases/<RELEASE_ID>/assets"
for f in downloads/DiaryAi-v1.0.5.apk downloads/DiaryAi-v1.0.5.zip; do
  name=$(basename "$f")
  ct=$([ "${f##*.}" = "apk" ] && echo "application/vnd.android.package-archive" || echo "application/zip")
  curl -s -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Content-Type: $ct" \
    --data-binary "@$f" "$UPLOAD_URL?name=$name" > /dev/null
  echo "uploaded $name"
done

# Проверка — должны появиться оба ассета
curl -s -H "Authorization: Bearer $GH_TOKEN" \
  https://api.github.com/repos/Zumka1991/DiaryAI/releases/tags/v1.0.5 \
  | python -c "import sys,json; [print(a['name'], a['size']) for a in json.load(sys.stdin)['assets']]"
```

## После релиза — деплой лендинга

Чтобы новые ссылки попали на `https://diaryai.ru`, надо передеплоить сайт. См. скилл `deploy`:

```bash
ssh -i ~/.ssh/id_ed25519 root@5.253.59.251 \
  "cd /apps/DiaryAI && git pull --ff-only && cd site && docker compose up -d --build"
```

## Гочи

- **Размеры на сайте** в `dl-meta` (`.zip · 13 МБ`, `.apk · 23 МБ`) — обновляй вручную, если значимо изменились.
- **Сборка APK x86/arm32 не нужна** — целевая аудитория современных андроидов, arm64 хватает. Размер APK ~23 МБ.
- **Windows зип** — собираем ВСЁ из `Release/`, иначе приложение не запустится без зависимостей рядом с `.exe`.
- **iOS** — пока не публикуем, нет Apple-аккаунта. `Info.plist` обновляем для consistency.
- **Тэг и версия в pubspec должны совпадать** — иначе в about-экране приложения отобразится не то, что в релизе.
- **Не делай `git push --tags` без явного нужного тега** — может протолкнуть локальные тесты-теги.
