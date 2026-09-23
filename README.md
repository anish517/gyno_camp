# GynoCamp (स्त्रीरोग स्वास्थ्य शिविर व्यवस्थापन प्रणाली)
### Enterprise Production Server Deployment & DevOps Engineering Guide

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-336791?logo=postgresql)](https://www.postgresql.org)
[![Nginx](https://img.shields.io/badge/Web_Server-Nginx-009639?logo=nginx)](https://nginx.org)
[![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker)](https://www.docker.com)
[![Google Gemini](https://img.shields.io/badge/OCR_AI-Google_Gemini_Flash-8E75B2?logo=googlegemini)](https://ai.google.dev)
[![License](https://img.shields.io/badge/License-Proprietary-red)](#)

> **Enterprise-grade, Offline-First Women's Health Outreach & Pelvic Organ Prolapse (POP-Q) Clinical Triage Platform.**  
> Designed for medical teams conducting remote mobile health camps across Nepal's mountainous topography. Operates 100% offline in the field with local SQLite storage, synchronizes bidirectionally with a dedicated Central PostgreSQL server when connected, and features AI-assisted Yellow Intake Form OCR scanning powered by Google Gemini.

---

## Table of Contents

1. [System Architecture & Network Topology](#1-system-architecture--network-topology)
2. [Server Prerequisites & Hardware Sizing](#2-server-prerequisites--hardware-sizing)
3. [Google Gemini OCR API Setup & Verification](#3-google-gemini-ocr-api-setup--verification)
4. [Phase 1: PostgreSQL Database Server Setup](#4-phase-1-postgresql-database-server-setup)
5. [Phase 2: Central Sync API Server Deployment (`bin/server.dart`)](#5-phase-2-central-sync-api-server-deployment-binserverdart)
   - [Method A: Systemd Daemon on Linux VPS (Recommended)](#method-a-systemd-daemon-on-linux-vps-recommended)
   - [Method B: Docker & Docker Compose](#method-b-docker--docker-compose)
6. [Phase 3: Flutter Web App Build & Nginx Reverse Proxy Deployment](#6-phase-3-flutter-web-app-build--nginx-reverse-proxy-deployment)
7. [Phase 4: SSL/TLS Certificate Configuration (Certbot & HTTPS)](#7-phase-4-ssltls-certificate-configuration-certbot--https)
8. [Phase 5: Android Client Release Compilation (APK & AAB)](#8-phase-5-android-client-release-compilation-apk--aab)
9. [DevOps Code Review & Automated Quality Gates](#9-devops-code-review--automated-quality-gates)
10. [Environment Variables & Configuration Matrix](#10-environment-variables--configuration-matrix)
11. [DevOps Operational Runbook & Troubleshooting](#11-devops-operational-runbook--troubleshooting)

---

## 1. System Architecture & Network Topology

```
                                  ┌──────────────────────────────────────────────┐
                                  │      Google Gemini 1.5 Flash AI API          │
                                  │   (Multimodal Yellow Form OCR Engine)        │
                                  └──────────────────────▲───────────────────────┘
                                                         │ HTTPS REST (via API Key)
┌────────────────────────────────────────┐               │               ┌────────────────────────────────────────┐
│      Flutter Web Client (Admin/Analyst)│               │               │      Android Field Tablet / Mobile     │
│  - Super Admin Command Console         │               │               │  - Field Nurse Patient Registration    │
│  - Clinical Data Analyst Workstation   │               │               │  - 6-Station Clinical Assessment Form  │
│  - Storage: IndexedDB / SQLite Wasm    │               │               │  - Storage: Embedded Local SQLite      │
└───────────────────┬────────────────────┘               │               └───────────────────┬────────────────────┘
                    │                                    │                                   │
                    │ HTTPS (api.yourdomain.org)         │                                   │ HTTPS (api.yourdomain.org)
                    └──────────────────────────┐         │         ┌─────────────────────────┘
                                               ▼         │         ▼
                                  ┌──────────────────────┴───────────────────────┐
                                  │          Nginx Ingress & SSL Proxy           │
                                  │  - Port 443 (HTTPS + TLS 1.3 + Certbot)      │
                                  │  - Serves compiled Flutter Web SPA           │
                                  │  - Reverse-proxies /api/* to Dart Sync Engine│
                                  └──────────────────────┬───────────────────────┘
                                                         │ HTTP Reverse Proxy (127.0.0.1:8080)
                                                         ▼
                                  ┌──────────────────────────────────────────────┐
                                  │       GynoCamp Central Sync Server           │
                                  │            (`bin/server.dart`)               │
                                  │  - Port 8080 (Dart Standalone Runtime)       │
                                  │  - Bidirectional Pull/Push Engine            │
                                  │  - Hardware Whitelist Gatekeeper             │
                                  │  - Cryptographic Tombstone Synchronization   │
                                  └──────────────────────┬───────────────────────┘
                                                         │ TCP Pool (localhost:5432)
                                                         ▼
                                  ┌──────────────────────────────────────────────┐
                                  │         PostgreSQL Database Engine           │
                                  │   Tables: camps, patients, clinical_visits,  │
                                  │           users, devices, lookup_items,      │
                                  │           deleted_entities, audit_logs       │
                                  └──────────────────────────────────────────────┘
```

---

## 2. Server Prerequisites & Hardware Sizing

### Recommended Server Specifications (Single-Node or Cloud VPS)
- **Operating System**: Ubuntu 22.04 LTS / 24.04 LTS, Debian 12, or AlmaLinux 9
- **CPU**: 2 vCPUs minimum (4 vCPUs recommended for multi-camp concurrent sync)
- **RAM**: 4 GB RAM minimum (8 GB recommended for PostgreSQL buffer cache + Dart runtime)
- **Storage**: 50 GB NVMe SSD minimum (with scheduled automated pg_dump backups)
- **Network**: Static IPv4 Address, Ports `80` (HTTP), `443` (HTTPS), and `22` (SSH) open.
- **DNS Records Configured**:
  - `app.yourdomain.org` (Pointing to server IP for Flutter Web)
  - `api.yourdomain.org` (Pointing to server IP for Central Sync API)

### Base Software Requirements on the Server
```bash
sudo apt update && sudo apt install -y curl git ufw nginx postgresql postgresql-contrib certbot python3-certbot-nginx
```

---

## 3. Google Gemini OCR API Setup & Verification

GynoCamp features a built-in **AI Multimodal Optical Scanner** (`lib/core/services/gemini_ocr_service.dart`) that parses photographs of Ministry of Health and Population (MoHP) paper **Yellow Forms**, extracting demographics, vitals, pelvic examination findings, POP stages, and prescribed medications.

### Step 3.1: Obtain Your Google Gemini API Key
1. Navigate to **[Google AI Studio](https://aistudio.google.com/)** and log in with your organization's Google account.
2. Click **"Get API key"** in the left sidebar.
3. Select **"Create API key in new project"** (or select your existing Google Cloud Project).
4. Copy the generated key string (format: `AIzaSy...` or `AQ.Ab8RN6Ku...`).

### Step 3.2: Verify the API Key with a Quick Curl Test
Before building the apps, test the key directly from your terminal:
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=YOUR_GEMINI_API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": [{
      "parts":[{"text": "Echo: GynoCamp OCR System Online"}]
    }]
  }'
```
*Expected Output*: A JSON response containing `"GynoCamp OCR System Online"`.

### Step 3.3: How the Key is Consumed by GynoCamp
- **At Build Time (Web & Android)**:
  Injected securely using the compile-time flag:
  ```bash
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
  ```
- **At Runtime (Dynamic Override)**:
  Medical directors can dynamically enter or rotate the Gemini key at any time in the app under **Settings / Session Service**, without requiring an app rebuild.

---

## 4. Phase 1: PostgreSQL Database Server Setup

### Step 4.1: Configure PostgreSQL
```bash
# Switch to postgres user
sudo -u postgres psql

# Run database creation commands inside psql:
CREATE DATABASE gynocamp_db;
CREATE USER gynoadmin WITH ENCRYPTED PASSWORD 'YourStrongDbPassword123!';
GRANT ALL PRIVILEGES ON DATABASE gynocamp_db TO gynoadmin;
ALTER DATABASE gynocamp_db OWNER TO gynoadmin;
\q
```

### Step 4.2: Optimize Connection & Local Security
Edit `/etc/postgresql/*/main/pg_hba.conf` to allow local password authentication:
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   gynocamp_db     gynoadmin                               md5
host    gynocamp_db     gynoadmin       127.0.0.1/32            scram-sha-256
```
Restart PostgreSQL:
```bash
sudo systemctl restart postgresql
sudo systemctl enable postgresql
```

> **Automated Schema Provisioning**:  
> The GynoCamp backend (`bin/server.dart`) automatically executes `CREATE TABLE IF NOT EXISTS` and index migrations on startup. Manual SQL table execution is not required.

---

## 5. Phase 2: Central Sync API Server Deployment (`bin/server.dart`)

The Central Sync Server is a high-performance native Dart service listening on port `8080`.

### Method A: Systemd Daemon on Linux VPS (Recommended)

#### Step 1: Install Dart SDK on Server
```bash
# Add Dart repository
sudo apt update
sudo apt install apt-transport-https
sudo sh -c 'wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg'
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list

sudo apt update && sudo apt install -y dart
dart --version
```

#### Step 2: Clone Codebase to `/opt/gynocamp`
```bash
sudo git clone https://github.com/anish517/gyno_camp.git /opt/gynocamp
cd /opt/gynocamp/gyno_camp

# Fetch dependencies
sudo dart pub get

# Compile native binary for maximum performance (optional but recommended)
sudo dart compile exe bin/server.dart -o /opt/gynocamp/gyno_camp/bin/gynocamp_server
```

#### Step 3: Create Systemd Service File
Create `/etc/systemd/system/gynocamp-api.service`:
```ini
[Unit]
Description=GynoCamp Central Cloud Synchronization REST API
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gynocamp/gyno_camp
ExecStart=/opt/gynocamp/gyno_camp/bin/gynocamp_server
Restart=always
RestartSec=5s

# Production Environment Variables
Environment=PORT=8080
Environment=PGHOST=127.0.0.1
Environment=PGPORT=5432
Environment=PGDATABASE=gynocamp_db
Environment=PGUSER=gynoadmin
Environment=PGPASSWORD=YourStrongDbPassword123!

# Resource & File Descriptor Limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

#### Step 4: Enable & Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable gynocamp-api
sudo systemctl start gynocamp-api
sudo systemctl status gynocamp-api
```

#### Step 5: Test the API Endpoint Locally
```bash
curl http://127.0.0.1:8080/health
```
*Expected Response*:
```json
{
  "status": "online",
  "service": "GynoCamp Central Cloud Synchronization API",
  "postgres_connected": true,
  "database": "gynocamp_db"
}
```

---

### Method B: Docker & Docker Compose

If using container orchestration, create `docker-compose.yml` on your server:

```yaml
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    container_name: gynocamp-postgres
    restart: always
    environment:
      POSTGRES_DB: gynocamp_db
      POSTGRES_USER: gynoadmin
      POSTGRES_PASSWORD: YourStrongDbPassword123!
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"

  sync_server:
    build:
      context: ./gyno_camp
      dockerfile: Dockerfile
    container_name: gynocamp-api
    restart: always
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      PORT: 8080
      PGHOST: db
      PGPORT: 5432
      PGDATABASE: gynocamp_db
      PGUSER: gynoadmin
      PGPASSWORD: YourStrongDbPassword123!
    depends_on:
      - db

volumes:
  pgdata:
```

Launch with:
```bash
docker compose up -d --build
```

---

## 6. Phase 3: Flutter Web App Build & Nginx Reverse Proxy Deployment

Instead of third-party platforms like Vercel, host the Flutter Web application directly on your server using **Nginx**.

### Step 6.1: Compile Flutter Web on Development Machine or CI/CD Server
Run this build command on your workstation (or CI pipeline) with your production domain and Gemini API key:

```bash
cd gyno_camp

flutter build web --release --no-wasm-dry-run \
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org \
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

*Output directory*: `build/web/`

### Step 6.2: Transfer Web Assets to the Server
```bash
# Upload compiled bundle to web directory
rsync -avz --delete build/web/ user@your-server-ip:/var/www/gynocamp-web/
```

### Step 6.3: Configure Nginx Virtual Host
Create `/etc/nginx/sites-available/gynocamp`:

```nginx
# 1. Web Application (Super Admin & Data Analyst Console)
server {
    listen 80;
    server_name app.yourdomain.org;

    root /var/www/gynocamp-web;
    index index.html;

    # Gzip Compression for Fast Remote Camp Loading
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, no-transform";
    }
}

# 2. Central Cloud Sync REST API
server {
    listen 80;
    server_name api.yourdomain.org;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket & Long Polling Support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Max payload size for OCR image sync
        client_max_body_size 25M;
        proxy_read_timeout 90s;
    }
}
```

Enable the configuration:
```bash
sudo ln -s /etc/nginx/sites-available/gynocamp /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

---

## 7. Phase 4: SSL/TLS Certificate Configuration (Certbot & HTTPS)

> ⚠️ **CRITICAL SECURITY REQUIREMENT**:  
> Web browsers block cross-origin requests between HTTP and HTTPS (Mixed Content). Both the Web App and Central API **must** have valid HTTPS SSL certificates.

Run Certbot to automatically provision and renew Let's Encrypt certificates:

```bash
sudo certbot --nginx -d app.yourdomain.org -d api.yourdomain.org
```

Certbot will automatically update the Nginx configuration, enforce HTTP to HTTPS redirection, and set up automatic renewal cron jobs.

Test HTTPS endpoints:
```bash
curl https://api.yourdomain.org/health
```

---

## 8. Phase 5: Android Client Release Compilation (APK & AAB)

Field workers run GynoCamp on Android tablets and smartphones.

### Step 8.1: Keystore Setup (One-time only)
```powershell
cd gyno_camp
keytool -genkey -v ^
  -keystore android\app\gynocamp-release.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias gynocamp ^
  -dname "CN=GynoCamp, OU=Clinical Outreach, O=Nepal Health Outreach Network, L=Kathmandu, S=Bagmati, C=NP"
```

### Step 8.2: Build Standalone Production APK (Direct USB / Sideloading)
```powershell
flutter build apk --release ^
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org ^
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```
File created: `build/app/outputs/flutter-apk/app-release.apk`

### Step 8.3: Build Google Play Store App Bundle (`.aab`)
```powershell
flutter build appbundle --release ^
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org ^
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```
File created: `build/app/outputs/bundle/release/app-release.aab`

---

## 9. DevOps Code Review & Automated Quality Gates

Every code change must pass static analysis and the automated test suite before deployment.

```bash
# 1. Run static code analyzer (Must exit with 0 issues)
flutter analyze

# 2. Run automated test suite (367+ tests)
flutter test

# 3. Targeted test suites
flutter test test/views/camp_report_view_responsive_test.dart
flutter test test/views/patient_registration_empty_validation_test.dart
flutter test test/services/gemini_ocr_service_test.dart
```

### Pre-Deployment Checklist
- [ ] `flutter analyze` completed with 0 errors and 0 warnings.
- [ ] All 367 tests passed successfully.
- [ ] Central server `/health` returns `"postgres_connected": true`.
- [ ] `CENTRAL_SERVER_URL` in web build starts with `https://`.
- [ ] `GEMINI_API_KEY` is tested and verified.
- [ ] Super Admin credentials (`admin@gynocamp.org` / `admin123`) verified.
- [ ] Root Super Admin role is protected and locked from demotion.

---

## 10. Environment Variables & Configuration Matrix

| Variable Name | Component | Injection Method | Default Value | Description |
|:---|:---|:---|:---|:---|
| `CENTRAL_SERVER_URL` | Web / Android | `--dart-define` | `http://localhost:8080` | Complete HTTPS URL to the Central Sync API |
| `GEMINI_API_KEY` | Web / Android | `--dart-define` | `""` | Google Cloud API key for Yellow Form AI OCR |
| `PORT` | Central API | Systemd / Shell env | `8080` | Port on which the Dart sync server listens |
| `PGHOST` | Central API | Systemd / Shell env | `127.0.0.1` | PostgreSQL database hostname or IP |
| `PGPORT` | Central API | Systemd / Shell env | `5432` | PostgreSQL database port |
| `PGDATABASE` | Central API | Systemd / Shell env | `gynocamp_db` | PostgreSQL database name |
| `PGUSER` | Central API | Systemd / Shell env | `gynoadmin` | PostgreSQL user account |
| `PGPASSWORD` | Central API | Systemd / Shell env | `""` | PostgreSQL user password |

---

## 11. DevOps Operational Runbook & Troubleshooting

### Problem 1: "Mixed Content" error on Web console
- **Symptom**: Web client fails to sync; browser logs `Blocked loading mixed active content`.
- **Cause**: Web app was compiled with an `http://` server URL instead of `https://`.
- **Remedy**: Rebuild Flutter Web ensuring `--dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org`.

### Problem 2: `/health` returns `"postgres_connected": false`
- **Symptom**: Sync server runs, but PostgreSQL queries fail.
- **Remedy**:
  1. Check PostgreSQL service status: `sudo systemctl status postgresql`.
  2. Verify credentials manually: `psql -h 127.0.0.1 -U gynoadmin -d gynocamp_db`.
  3. Ensure `/etc/systemd/system/gynocamp-api.service` has the correct `PGPASSWORD`.

### Problem 3: Yellow Form OCR returns "Invalid API Key" or HTTP 403
- **Symptom**: Taking photo of yellow form in mobile app gives OCR scan error.
- **Remedy**:
  1. Check if Gemini API key has expired or billing is paused in Google AI Studio.
  2. Run the curl test in [Section 3.2](#step-32-verify-the-api-key-with-a-quick-curl-test).
  3. Verify the app was compiled with `--dart-define=GEMINI_API_KEY=...` or update the key in the app under **Settings**.

### Problem 4: Android device shows "Awaiting Super Admin Approval"
- **Symptom**: Field nurse attempts to login from a new tablet and sees a security hold.
- **Cause**: GynoCamp enforces zero-trust hardware whitelisting for all clinical field devices.
- **Remedy**: Log into the Web Console as Super Admin (`admin@gynocamp.org`), go to **Device Security & Whitelist**, and click **Authorize Device**. The tablet will auto-detect approval within 2–3 seconds.

---

## Support & Maintainer
Developed for **Nepal Health Outreach Network** & Rural Mobile Gynecological Camps.  
Maintained by Engineering & DevOps. All rights reserved.
