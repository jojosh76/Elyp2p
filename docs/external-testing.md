# External Testing Delivery Pack

## What ships to testers
- APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`

## What must run on server
- Go API (`backend/cmd/api`)
- Postgres database

## Quick deploy (Docker Compose)

1. Copy env template:

```bash
cp backend/.env.production.example backend/.env.production
```

2. Edit `backend/.env.production`:
- `JWT_SECRET`
- `UPLOAD_SIGNING_SECRET`
- `PAYMENT_PROVIDER`
- Stripe keys/URLs if using Stripe

3. Start stack:

```bash
docker compose -f deploy/docker-compose.external-test.yml up -d --build
```

4. Verify:

```bash
curl http://YOUR_SERVER:8080/healthz
```

## Build APK with server URL

From `mobile/`:

```powershell
.\scripts\build_release_apk.ps1 -ApiBaseUrl "https://YOUR_PUBLIC_API_URL"
```

## Optional production signing

Use:
- `mobile/android/key.properties.example`

Create `mobile/android/key.properties` and keystore file, then rebuild APK.
