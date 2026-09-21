# GynoCamp — Production Deployment Guide

> **Deploy Order:** Server → Web → Android. Always in this sequence.

---

## Overview

```
WHAT YOU DEPLOY          WHERE                    COST
─────────────────────────────────────────────────────────
bin/server.dart          Railway.app              ~$5/month
PostgreSQL database      Railway.app (add-on)     Free tier
Flutter Web app          Vercel                   Free
Android APK              Google Play Store        $25 one-time
```

---

## PHASE 1 — Deploy Sync Server (`bin/server.dart`) to Railway

### Step 1.1 — Push your code to GitHub

If not already done:

```bash
cd f:\gyno_camp
git init
git add .
git commit -m "initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/gyno_camp.git
git push -u origin main
```

### Step 1.2 — Create Railway account

1. Go to **https://railway.app**
2. Click **"Start a New Project"**
3. Sign in with GitHub (recommended — it links your repos)

### Step 1.3 — Add PostgreSQL Database

1. Inside your Railway project, click **"+ New"**
2. Select **"Database" → "Add PostgreSQL"**
3. Wait ~30 seconds for it to provision
4. Click on the PostgreSQL service → **"Variables"** tab
5. Note down these values (Railway generates them):
   ```
   PGHOST     = containers-us-west-XXX.railway.internal
   PGPORT     = 5432
   PGDATABASE = railway
   PGUSER     = postgres
   PGPASSWORD = xxxxxxxxxxxxxxxx
   ```

### Step 1.4 — Deploy the Dart Sync Server

1. Click **"+ New"** → **"GitHub Repo"**
2. Select your `gyno_camp` repository
3. Railway will try to auto-detect. Set the build settings manually:
   - Go to **Settings → Build**
   - **Build Command:** `dart pub get`
   - **Start Command:** `dart run bin/server.dart`
   - **Root Directory:** `gyno_camp`

4. Go to the **"Variables"** tab on your server service and add:

   | Variable | Value |
   |----------|-------|
   | `PORT` | `8080` |
   | `PGHOST` | *(paste internal hostname from PostgreSQL service)* |
   | `PGPORT` | `5432` |
   | `PGDATABASE` | `railway` |
   | `PGUSER` | `postgres` |
   | `PGPASSWORD` | *(paste from PostgreSQL service)* |

   > ⚠️ For `PGHOST`, use the **`.railway.internal`** hostname — both services are on the same Railway network so it is faster and free.

5. Click **"Deploy"**. Watch the build log — you should see:
   ```
   ✓ Successfully connected to central PostgreSQL database (railway).
   ✓ Central Cloud Sync API listening on http://0.0.0.0:8080
   ```

### Step 1.5 — Get Your Public HTTPS Server URL

1. In Railway, click your server service → **"Settings"** tab
2. Under **"Networking"**, click **"Generate Domain"**
3. You will get a URL like:
   ```
   https://gyno-camp-sync-production.up.railway.app
   ```
4. **Save this URL — you will use it in every build from now on.**

### Step 1.6 — Verify the Server is Working

Open in browser:
```
https://gyno-camp-sync-production.up.railway.app/health
```

Expected response:
```json
{
  "status": "online",
  "service": "GynoCamp Central Cloud Synchronization API",
  "postgres_connected": true,
  "database": "railway"
}
```

> ❌ If `postgres_connected` is `false` → check the `PGHOST` value. It must be the Railway internal hostname, not `localhost`.

---

## PHASE 2 — Deploy Web App to Vercel

### Step 2.1 — Update `vercel-build.sh` to accept environment variables

Edit [`gyno_camp/vercel-build.sh`](file:///f:/gyno_camp/gyno_camp/vercel-build.sh) — change the build line to:

```bash
flutter build web --release \
  --dart-define=CENTRAL_SERVER_URL=$CENTRAL_SERVER_URL \
  --dart-define=GEMINI_API_KEY=$GEMINI_API_KEY \
  --no-wasm-dry-run
```

Commit and push this change to GitHub.

### Step 2.2 — Create Vercel account and import project

1. Go to **https://vercel.com** → Sign up with GitHub
2. Click **"Add New Project"**
3. Import your `gyno_camp` GitHub repository
4. Verify these settings (auto-detected from `vercel.json`):
   - **Build Command:** `cd gyno_camp && bash vercel-build.sh`
   - **Output Directory:** `gyno_camp/build/web`

### Step 2.3 — Set Vercel Environment Variables

Go to **Settings → Environment Variables** and add:

| Name | Value |
|------|-------|
| `CENTRAL_SERVER_URL` | `https://gyno-camp-sync-production.up.railway.app` |
| `GEMINI_API_KEY` | `your-gemini-api-key` |

### Step 2.4 — Deploy

Click **"Deploy"**. Vercel builds and publishes. Takes ~3-5 minutes.

Your web app will be live at:
```
https://gyno-camp.vercel.app
```

### Step 2.5 — Test Web Sync

1. Open the Vercel URL in Chrome
2. Log in → register a test patient
3. Go to **Sync screen** → trigger sync
4. Check Railway logs — patient should appear in PostgreSQL

---

## PHASE 3 — Build Android APK for Play Store

### Step 3.1 — Generate a signing keystore (ONE TIME ONLY)

> ⚠️ Do this only once. **Back up the `.jks` file securely. Without it, you can never update your Play Store app.**

```bash
cd f:\gyno_camp\gyno_camp

keytool -genkey -v ^
  -keystore android\app\gynocamp-release.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias gynocamp ^
  -dname "CN=GynoCamp, OU=Health, O=YourOrg, L=Kathmandu, S=Bagmati, C=NP"
```

Enter a strong password when prompted. Remember it.

### Step 3.2 — Configure release signing

Edit [`android/app/build.gradle.kts`](file:///f:/gyno_camp/gyno_camp/android/app/build.gradle.kts):

```kotlin
android {
    namespace = "np.org.gynocamp.app"      // ← change from com.example.gyno_camp
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = "gynocamp"
            keyPassword = "YOUR_KEY_PASSWORD"
            storeFile = file("gynocamp-release.jks")
            storePassword = "YOUR_STORE_PASSWORD"
        }
    }

    defaultConfig {
        applicationId = "np.org.gynocamp.app"    // ← must be unique, never com.example.*
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")  // ← was "debug"
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
```

### Step 3.3 — Add keystore to `.gitignore`

```bash
echo android/app/gynocamp-release.jks >> f:\gyno_camp\gyno_camp\.gitignore
```

> ⚠️ **Never commit your `.jks` file to GitHub.**

### Step 3.4 — Build the App Bundle for Play Store

```bash
cd f:\gyno_camp\gyno_camp

flutter build appbundle --release ^
  --dart-define=CENTRAL_SERVER_URL=https://gyno-camp-sync-production.up.railway.app ^
  --dart-define=GEMINI_API_KEY=your-gemini-api-key
```

Output file:
```
build\app\outputs\bundle\release\app-release.aab
```

### Step 3.5 — (Optional) Build plain APK for direct testing

```bash
flutter build apk --release ^
  --dart-define=CENTRAL_SERVER_URL=https://gyno-camp-sync-production.up.railway.app ^
  --dart-define=GEMINI_API_KEY=your-gemini-api-key
```

Test on device:
```bash
adb install build\app\outputs\flutter-apk\app-release.apk
```

### Step 3.6 — Verify before uploading

- [ ] App opens and reaches login screen
- [ ] Login works with correct credentials
- [ ] Register a patient → syncs to Railway server
- [ ] Data registered on web appears after pull on Android

---

## PHASE 4 — Upload to Google Play Store

### Step 4.1 — Create Play Console account

1. Go to **https://play.google.com/console**
2. Pay the **$25 one-time developer registration fee**
3. Create a new app:
   - **App name:** GynoCamp
   - **Default language:** English
   - **App or game:** App
   - **Free or paid:** Free

### Step 4.2 — Upload the App Bundle

1. Play Console → your app → **"Production"** (left sidebar)
2. Click **"Create new release"**
3. Upload `app-release.aab`
4. Fill release details:
   - **Release name:** `1.0.0`
   - **Release notes:** `Initial release of GynoCamp gynaecological health camp management system`
5. Click **"Review release"** → **"Start rollout to Production"**
6. Google review takes **1–3 business days**

---

## Environment Variables — Full Reference

| Variable | Local Dev | Railway (server) | Vercel (web build) | APK build |
|----------|-----------|------------------|--------------------|-----------|
| `CENTRAL_SERVER_URL` | `http://192.168.110.108:8080` | *(not needed — it IS the server)* | `https://gyno-camp-sync-production.up.railway.app` | Same as Vercel |
| `PGHOST` | `localhost` | Railway internal hostname | *(not needed)* | *(not needed)* |
| `PGDATABASE` | `gynocamp_db` | `railway` | *(not needed)* | *(not needed)* |
| `PGPASSWORD` | `postgres` | Railway generated | *(not needed)* | *(not needed)* |
| `GEMINI_API_KEY` | from `local_env.bat` | *(not needed)* | Set in Vercel dashboard | In build command |

---

## Cost Summary

| Service | Plan | Monthly Cost |
|---------|------|-------------|
| Railway — Dart server | Starter | ~$5/month |
| Railway — PostgreSQL | Free (1 GB) | $0 |
| Vercel — Web hosting | Hobby (free) | $0 |
| Google Play Store | One-time fee | $25 (once only) |
| **Total running cost** | | **~$5/month** |

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Chrome shows `Mixed Content` error | Web (HTTPS Vercel) calling HTTP server | Ensure `CENTRAL_SERVER_URL` starts with `https://` |
| Android says "Cannot connect to server" | APK built without `--dart-define` | Rebuild with the Railway HTTPS URL |
| `postgres_connected: false` on `/health` | Wrong `PGHOST` on Railway | Use `.railway.internal` hostname, not `localhost` |
| Play Store rejects AAB | Debug signing key used | Complete Step 3.2 with release keystore |
| Play Store rejects app ID | `com.example.*` is blocked | Change `applicationId` to `np.org.gynocamp.app` |
| Vercel build fails | `$CENTRAL_SERVER_URL` not set | Add it in Vercel → Settings → Environment Variables |

---

## Quick Reference — Rebuild After Code Changes

```bash
# Push new code → Railway and Vercel auto-redeploy
git add .
git commit -m "your change"
git push origin main

# Rebuild Android APK after code changes
cd f:\gyno_camp\gyno_camp
flutter build apk --release ^
  --dart-define=CENTRAL_SERVER_URL=https://gyno-camp-sync-production.up.railway.app ^
  --dart-define=GEMINI_API_KEY=your-gemini-api-key

# Rebuild App Bundle for Play Store update
flutter build appbundle --release ^
  --dart-define=CENTRAL_SERVER_URL=https://gyno-camp-sync-production.up.railway.app ^
  --dart-define=GEMINI_API_KEY=your-gemini-api-key
```
