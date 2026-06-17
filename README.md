# P2P Traveler Delivery Platform

This repository contains an MVP for a peer-to-peer package delivery platform where travelers carry client packages for a fee.

## Core Product Features

- Traveler listings (weight, destination city/country, travel dates)
- Client delivery requests by destination
- Escrow payments with platform commission
- Traveler KYC with passport and permanent residence documents
- Package verification workflow (risk score + admin approval/rejection)
- Delivery tracking timeline events
- Admin moderation console endpoints (KYC/package review, users, escrows, commissions)

## Suggested Stack

- Mobile app: Flutter
- Backend API: Go
- Recommended additions:
  - Postgres (durable transactional data)
  - Redis (locks, idempotency, queues)
  - Background worker (Go) for async workflows

## Repository Layout

- `backend/`: Go API with JWT auth, role-based routes, in-memory/Postgres repositories, moderation workflows, and commission summary.
- `docs/`: Architecture and rollout documentation.
- `mobile/`: Flutter UI scaffold with user and admin dashboards.

## Run Backend

```bash
cd backend
go run ./cmd/api
```

Server starts on `http://localhost:8080`.

### Environment Variables

- `API_ADDR` (default `:8080`)
- `COMMISSION_RATE` (default `0.10`)
- `JWT_SECRET` (default `change-me-in-production`)
- `JWT_TTL` (default `72h`)
- `ALLOW_INSECURE_DEV` (default `false`; set `true` only for local dev)
- `DATABASE_URL` (optional; if omitted, memory store is used)
- `AUTH_MAX_FAILS` (default `5`)
- `AUTH_LOCK_WINDOW` (default `15m`)
- `OTP_MAX_FAILS` (default `5`)
- `OTP_LOCK_WINDOW` (default `15m`)
- `UPLOAD_SIGNING_SECRET` (default `JWT_SECRET`)
- `UPLOADS_DIR` (default `data/uploads`)
- `UPLOAD_TOKEN_TTL` (default `15m`)

Example `DATABASE_URL`:

```bash
postgres://postgres:postgres@localhost:5432/p2p_delivery?sslmode=disable
```

### API Routes

See `backend/API.md` for full endpoint list.

## External Tester Setup (APK + Backend + DB)

You cannot bundle backend/database inside an APK.  
For external phone testing, deploy backend + Postgres on a reachable server, then build APK with that API URL.

### 1) Deploy backend + Postgres with Docker

Files added:
- `deploy/docker-compose.external-test.yml`
- `backend/Dockerfile`
- `backend/.env.production.example`

Steps:

```bash
cp backend/.env.production.example backend/.env.production
# edit backend/.env.production values (JWT_SECRET, provider keys, URLs, etc.)
docker compose -f deploy/docker-compose.external-test.yml up -d --build
```

API will be on server port `8080` (or behind your reverse proxy/domain).

### 2) Build shareable APK

From `mobile/`:

```powershell
.\scripts\build_release_apk.ps1 -ApiBaseUrl "https://YOUR_PUBLIC_API_URL"
```

Output:
- `mobile/build/app/outputs/flutter-apk/app-release.apk`

### 3) Optional proper release signing

If `mobile/android/key.properties` exists, release build uses your keystore.
If not, it falls back to debug signing.

Create from template:
- `mobile/android/key.properties.example`

## Mobile Screens Implemented

- Auth (register/login with role)
- User dashboard:
  - Traveler listings (create/list)
  - Delivery requests (create/list)
  - My work (my listings/requests/matches/escrows + match/escrow actions)
  - KYC submit + status history
  - Package verification submit + history
  - Tracking timeline
- Admin dashboard:
  - KYC review queue
  - Package verification review queue
  - Finance dashboard (escrows, commission summary, user list)

## Important Risk and Compliance Notes

- This model has legal/compliance exposure by country (customs, carrier rules, controlled goods).
- KYC/AML and sanctions screening are required before production launch.
- Package verification should combine:
  - required declaration with legal attestation
  - document/receipt upload
  - risk scoring
  - optional physical inspection at partner points
- Escrow must use licensed payment providers.

This code is an MVP scaffold, not production-ready compliance infrastructure.
