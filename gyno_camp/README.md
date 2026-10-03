# GynoCamp (स्त्रीरोग स्वास्थ्य शिविर व्यवस्थापन प्रणाली)

A gynaecological health camp management system for Nepal, supporting offline-first field tablets, a central PostgreSQL sync server, cloud OCR (Gemini), and SMTP-based staff password reset.

---

## Architecture

```
[Field Tablets / Web Browsers]
         ↓  HTTPS
[Flutter App]  →  [Dart Sync Server (bin/server.dart)]  →  [PostgreSQL]
                              ↓
                        [Gemini API]   ← key lives HERE only
                        [SMTP / Gmail]
```

---

## Quick Start (Local Development)

### 1. Prerequisites
- Flutter SDK ≥ 3.x
- Dart SDK ≥ 3.x
- PostgreSQL 14+

### 2. Clone & Install
```bash
git clone https://github.com/your-username/gyno_camp.git
cd gyno_camp
flutter pub get
```

### 3. Configure Server Secrets
```bash
cp server.env.example server.env
# Edit server.env and fill in your real values:
#   GEMINI_API_KEY, PGPASSWORD, SMTP_USER, SMTP_PASSWORD, etc.
```

### 4. Start the Sync Server
```bash
# Windows
start_sync_server.bat

# Linux / Mac
dart run bin/server.dart
```

### 5. Run the Flutter App
```bash
flutter run -d chrome --web-port=5000 \
  --dart-define=CENTRAL_SERVER_URL=http://localhost:8080
```

---

## Deployment Guide

### Option A: Railway (Easiest — Recommended)

1. Sign up at [railway.app](https://railway.app)
2. **New Project** → Deploy from GitHub → select this repo
3. Add a **PostgreSQL** plugin inside the project
4. Set environment variables in the Railway dashboard:
   ```
   GEMINI_API_KEY=AIzaSy...
   PGHOST=${{Postgres.PGHOST}}
   PGPORT=${{Postgres.PGPORT}}
   PGDATABASE=${{Postgres.PGDATABASE}}
   PGUSER=${{Postgres.PGUSER}}
   PGPASSWORD=${{Postgres.PGPASSWORD}}
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=your@gmail.com
   SMTP_PASSWORD=your-app-password
   SMTP_FROM_NAME=GynoCamp Security Network
   SMTP_FROM_EMAIL=your@gmail.com
   SMTP_SECURE=false
   PORT=8080
   HOST=0.0.0.0
   ```
5. Railway detects the `Dockerfile` and deploys automatically.
6. Your server URL: `https://your-project.railway.app`

### Option B: Render (Free Tier)

1. Sign up at [render.com](https://render.com)
2. New → **Web Service** → connect GitHub repo → Runtime: **Docker**
3. Add the same environment variables as above
4. Add a **PostgreSQL** database in Render dashboard
5. Your server URL: `https://your-app.onrender.com`

> ⚠️ Free tier sleeps after 15 min inactivity (~30s cold start)

### Option C: VPS / Cloud VM (DigitalOcean, AWS, Azure)

```bash
# On your Linux server:
sudo apt install dart postgresql -y

git clone https://github.com/your-username/gyno_camp.git
cd gyno_camp
cp server.env.example server.env
nano server.env   # fill in real values

dart pub get
dart run bin/server.dart
```

Keep it running with **systemd**:
```ini
# /etc/systemd/system/gynocamp.service
[Unit]
Description=GynoCamp Server

[Service]
WorkingDirectory=/home/ubuntu/gyno_camp
EnvironmentFile=/home/ubuntu/gyno_camp/server.env
ExecStart=/usr/bin/dart run bin/server.dart
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl enable gynocamp && sudo systemctl start gynocamp
```

### Option D: Docker Compose (Self-hosted)

```yaml
# docker-compose.yml
version: '3.8'
services:
  server:
    build: .
    ports:
      - "8080:8080"
    env_file:
      - server.env
    depends_on:
      - db
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: gynocamp_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: your-password
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```
```bash
docker-compose up -d
```

---

## Deploying the Flutter Web UI

After deploying the server, build and deploy the web UI:

```bash
flutter build web --release \
  --dart-define=CENTRAL_SERVER_URL=https://YOUR-SERVER-URL
```

Deploy the `build/web/` folder to:

| Platform | How |
|----------|-----|
| **Netlify** | Drag & drop `build/web/` at app.netlify.com |
| **GitHub Pages** | Push to `gh-pages` branch |
| **Firebase Hosting** | `firebase deploy` |
| **Nginx** | Copy to `/var/www/html/` |

---

## Build Commands

### Web
```bash
flutter build web --release \
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org
```

### Android APK (Field Tablets)
```bash
flutter build apk --release \
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org
```

---

## Security

- **Gemini API key** lives **only** on the server (`GEMINI_API_KEY` env var in `server.env`)
- `server.env` is in `.gitignore` — it is **never committed to GitHub**
- Apps call `POST /api/ocr/extract` on the central server; the server authenticates the device and applies rate limits before calling Gemini
- SMTP credentials also live only in `server.env`

---

## Code Quality

```bash
flutter analyze   # static analysis
flutter test      # unit tests
```

---

## Environment Variables Reference

See [`server.env.example`](./server.env.example) for the full list with descriptions.
