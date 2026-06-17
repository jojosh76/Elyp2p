# MVP Architecture and Rollout

## 1) Domain Workflow

1. Traveler completes KYC and can publish listings.
2. Client creates delivery request with declared package details.
3. Package verification runs risk checks.
4. Matching confirms weight, route, dates, and price.
5. Client funds escrow.
6. Tracking events are recorded during delivery.
7. Client confirms delivery, escrow releases minus platform commission.

## 2) Services

- Flutter app:
  - Auth + profile
  - Traveler listing screens
  - Client request screens
  - Tracking timeline
  - KYC/package document upload
- Go API:
  - Matching engine rules
  - Escrow lifecycle state machine
  - KYC + package verification status orchestration
  - Commission accounting
- Storage:
  - Postgres for core transactional entities
  - Object storage (S3-compatible) for documents/images
  - Redis for queues, idempotency, and locks

## 3) Escrow Model

- Escrow states:
  - `pending_funding`
  - `funded`
  - `released`
  - `refunded`
  - `disputed`
- Commission:
  - Calculated at escrow creation with configurable `commission_rate`.
  - Platform revenue = `escrow.amount * commission_rate`.

## 4) KYC and Safety Controls

- Traveler verification fields:
  - legal name
  - permanent residence address
  - passport details
  - selfie/liveness check
  - sanctions/PEP screening
- Package anti-drug controls:
  - mandatory content declaration + legal attestation
  - invoice/receipt upload
  - risk scoring rules (origin, route, item category, sender history)
  - suspicious package hold and manual review
  - optional partner inspection points at airports/hubs

## 5) Suggested Third-Party Integrations

- Payments/Escrow wallet: Stripe Connect, Mangopay, or Adyen MarketPay (country-dependent).
- KYC: Sumsub, Persona, Veriff, or Onfido.
- Address verification: Stripe Identity or Experian-like providers.
- Messaging/notifications: Firebase Cloud Messaging + email provider.

## 6) Immediate Build Plan

1. Implement payment webhooks and idempotent transaction handling.
2. Add background jobs for async verification checks.
3. Integrate object storage (S3-compatible) for uploads.
4. Add dispute operations tooling for admins.
5. Expand automated test coverage (unit + integration + e2e).
6. Prepare production release pipelines for backend and mobile.
