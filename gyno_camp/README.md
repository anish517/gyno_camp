# GynoCamp (स्त्रीरोग स्वास्थ्य शिविर व्यवस्थापन प्रणाली)
### Enterprise Production Server Deployment & DevOps Engineering Guide

Please refer to the primary repository documentation:
[Root Production Server & DevOps Deployment Guide (README.md)](../README.md)

---

## Quick Reference Commands

### Start Sync Server (Development)
```bash
dart run bin/server.dart
```

### Build Web for Dedicated Server (Nginx)
```bash
flutter build web --release --no-wasm-dry-run \
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org \
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

### Build Android APK for Field Tablets
```bash
flutter build apk --release \
  --dart-define=CENTRAL_SERVER_URL=https://api.yourdomain.org \
  --dart-define=GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

### Code Quality Gates
```bash
flutter analyze
flutter test
```
