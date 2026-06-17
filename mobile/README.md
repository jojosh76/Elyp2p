# Flutter App

This Flutter UI includes:

- Auth (register/login with `client`, `traveler`, `admin`)
- User dashboard:
  - Traveler listings
  - Delivery requests
  - My work (matches + escrows)
  - KYC submission
  - Package verification submission
  - Tracking
- Admin dashboard:
  - KYC review queue
  - Package review queue
  - Escrows + commission summary + users

## Run

```bash
flutter pub get
flutter run
```

If backend runs on another host/device, update `baseUrl` in `lib/src/app.dart`.

Preferred runtime override:

```bash
flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_IP>:8080
```
