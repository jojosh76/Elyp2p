# API Overview

Base URL: `http://localhost:8080`

## Auth

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/social`
- `POST /v1/auth/otp/verify`
- `GET /v1/auth/providers`
- `GET /v1/me`

## Public Listings/Requests

- `GET /v1/travelers/listings?destination=...`
- `GET /v1/clients/requests?destination=...`
- `GET /v1/tracking/{match_id}`

## User Endpoints (Bearer token)

- `GET /v1/me/listings`
- `GET /v1/me/requests`
- `GET /v1/me/matches`
- `GET /v1/me/escrows`
- `GET /v1/me/profile`
- `PUT /v1/me/profile`
- `GET /v1/me/kyc/verifications`
- `GET /v1/me/packages/verifications`
- `GET /v1/me/notifications`
- `GET /v1/me/notifications/unread-count`
- `POST /v1/me/notifications/{id}/read`
- `DELETE /v1/me/notifications/{id}`
- `GET /v1/me/payout-account`
- `POST /v1/uploads/presign`

### Traveler / Client Actions

- `POST /v1/travelers/listings`
- `POST /v1/clients/requests`
- `POST /v1/matches`
- `POST /v1/escrows`
- `POST /v1/escrows/{escrow_id}/fund`
- `POST /v1/escrows/{escrow_id}/release`
- `POST /v1/escrows/{escrow_id}/refund`
- `POST /v1/escrows/{escrow_id}/dispute`
- `POST /v1/kyc/verifications`
- `POST /v1/packages/verifications`
- `POST /v1/tracking/events`
- `POST /v1/payments/connect/onboard`
- `PUT /v1/uploads/{signed_token}` (direct binary upload after presign)

## Admin Endpoints

- `GET /v1/admin/users`
- `GET /v1/admin/escrows`
- `GET /v1/admin/commissions/summary`
- `GET /v1/admin/kyc/verifications?status=...`
- `POST /v1/admin/kyc/verifications/{id}/review` with `{ "status": "verified|rejected", "notes": "" }`
- `GET /v1/admin/packages/verifications?status=...`
- `POST /v1/admin/packages/verifications/{id}/review` with `{ "status": "approved|rejected|rejected_high_risk", "notes": "" }`
- `GET /v1/admin/oauth/providers`
- `PUT /v1/admin/oauth/providers/{provider}`

## Safety Rules Implemented

- Traveler must be KYC-verified before a match can be created.
- Package must be approved by package verification before a match can be created.
- Escrow release requires escrow to be funded first.
- Escrow refund requires escrow to be `funded` or `disputed`.
- Escrow dispute requires escrow to be `funded`.
- Escrow release is locked until tracking includes a `delivered` status.
- Commission summary is based on released escrows only.
