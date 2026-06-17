# Architecture Diagrams for Elyp2p

Ce document regroupe l’analyse de l’architecture backend/mobile du projet et génère 1 diagramme de cas d’utilisation, 1 diagramme de classes et 5 diagrammes de séquences.

## 1. Use Case Diagram

```mermaid
usecaseDiagram
  actor Client
  actor Traveler
  actor Admin
  actor "Mobile App" as MobileApp
  actor "Backend API" as Backend

  Client --> (Register / Login)
  Traveler --> (Register / Login)
  Admin --> (Register / Login)

  Client --> (Create Delivery Request)
  Traveler --> (Create Traveler Listing)
  Traveler --> (Submit KYC Verification)
  Client --> (Submit Package Verification)
  Traveler --> (Add Tracking Event)

  Client --> (Create Match)
  Client --> (Create Escrow)
  Client --> (Fund Escrow)
  Traveler --> (Release Escrow)

  Admin --> (Review KYC Verification)
  Admin --> (Review Package Verification)
  Admin --> (View Commission Summary)
  Admin --> (Manage Users)

  MobileApp --> Backend : HTTP REST API
  Backend --> (Register / Login)
  Backend --> (Create Traveler Listing)
  Backend --> (Create Delivery Request)
  Backend --> (Create Match)
  Backend --> (Create Escrow)
  Backend --> (Review Verifications)
  Backend --> (Tracking Events)
```

## 2. Class Diagram

```mermaid
classDiagram
  class Server {
    - repo: Repository
    - authManager: auth.Manager
    - paymentProvider: payments.Provider
    + Handler()
    + register()
    + login()
    + createTravelerListing()
    + createDeliveryRequest()
    + createMatch()
    + createEscrow()
    + createKYCVerification()
    + createPackageVerification()
    + addTrackingEvent()
    + createPayoutOnboarding()
  }

  class ApiClient {
    - baseUrl: String
    - token: String?
    - currentUser: Map<String, dynamic>?
    + register()
    + login()
    + createTravelerListing()
    + createDeliveryRequest()
    + createMatch()
    + createEscrow()
    + submitKYC()
    + submitPackageVerification()
    + addTrackingEvent()
  }

  class Manager {
    - secret: []byte
    - ttl: time.Duration
    + Issue(userID, role)
    + Parse(token)
  }

  class Repository {
    <<interface>>
    + CreateUser()
    + GetUserByEmail()
    + CreateTravelerListing()
    + CreateDeliveryRequest()
    + CreateMatch()
    + CreateEscrow()
    + CreateKYCVerification()
    + CreatePackageVerification()
    + AddTrackingEvent()
    + ListUsers()
    + ReviewKYCVerification()
    + ReviewPackageVerification()
  }

  class Provider {
    <<interface>>
    + CreateEscrowHold()
    + CreatePayoutOnboardingLink()
  }

  class User {
    + ID: string
    + Email: string
    + FullName: string
    + Role: UserRole
    + KYCStatus: string
    + PayoutProvider: string
    + PayoutAccountStatus: string
  }

  class TravelerListing {
    + ID: string
    + TravelerID: string
    + Origin: string
    + Destination: string
    + DepartureDate: time.Time
    + ArrivalDate: time.Time
    + MaxWeightKg: float64
    + PricePerKg: float64
  }

  class DeliveryRequest {
    + ID: string
    + ClientID: string
    + Origin: string
    + Destination: string
    + RecipientName: string
    + WeightKg: float64
    + DeclaredValue: float64
  }

  class Match {
    + ID: string
    + ListingID: string
    + RequestID: string
    + AgreedPrice: float64
    + Status: string
  }

  class Escrow {
    + ID: string
    + MatchID: string
    + Amount: float64
    + CommissionAmount: float64
    + TravelerAmount: float64
    + Status: string
  }

  class KYCVerification {
    + ID: string
    + UserID: string
    + DocumentType: string
    + Status: string
  }

  class PackageVerification {
    + ID: string
    + RequestID: string
    + DeclaredContents: string
    + RiskScore: int
    + Status: string
  }

  class TrackingEvent {
    + ID: string
    + MatchID: string
    + Status: string
    + Location: string
  }

  Server --> Repository
  Server --> Manager
  Server --> Provider
  ApiClient --> Server
  Repository <|.. MemoryStore
  Repository <|.. PostgresStore
  Provider <|.. NoopProvider
  Provider <|.. StripeConnectProvider
  Server ..> User
  Server ..> TravelerListing
  Server ..> DeliveryRequest
  Server ..> Match
  Server ..> Escrow
  Server ..> KYCVerification
  Server ..> PackageVerification
  Server ..> TrackingEvent
```

## 3. Sequence Diagrams

### 3.1 User Registration and Login

```mermaid
sequenceDiagram
  participant User
  participant MobileApp
  participant ApiClient
  participant Backend
  participant Repo
  participant AuthManager

  User->>MobileApp: fills register/login form
  MobileApp->>ApiClient: register()/login()
  ApiClient->>Backend: POST /v1/auth/register or /v1/auth/login
  Backend->>Repo: CreateUser() / GetUserByEmail()
  Repo->>Backend: returns User
  Backend->>AuthManager: Issue(userID, role)
  AuthManager-->>Backend: JWT token
  Backend-->>ApiClient: user + token
  ApiClient-->>MobileApp: authenticated session
  MobileApp-->>MobileApp: persistSession()
```

### 3.2 Traveler Listing Creation

```mermaid
sequenceDiagram
  participant Traveler
  participant MobileApp
  participant ApiClient
  participant Backend
  participant Repo
  participant Database

  Traveler->>MobileApp: opens listing form
  MobileApp->>ApiClient: createTravelerListing(details)
  ApiClient->>Backend: POST /v1/travelers/listings
  Backend->>Backend: authRequired(roleTravelerOrAdmin)
  Backend->>Repo: CreateTravelerListing(listing)
  Repo->>Database: insert traveler_listing row
  Database-->>Repo: created listing
  Repo-->>Backend: listing
  Backend-->>ApiClient: listing response
  ApiClient-->>MobileApp: show listing created
```

### 3.3 Delivery Request + Matching

```mermaid
sequenceDiagram
  participant Client
  participant MobileApp
  participant ApiClient
  participant Backend
  participant Repo
  participant Database

  Client->>MobileApp: submit delivery request
  MobileApp->>ApiClient: createDeliveryRequest(request)
  ApiClient->>Backend: POST /v1/clients/requests
  Backend->>Backend: authRequired(roleClientOrAdmin)
  Backend->>Repo: CreateDeliveryRequest(request)
  Repo->>Database: insert delivery_request row
  Database-->>Repo: request created
  Repo-->>Backend: request
  Backend-->>ApiClient: request response
  Client->>MobileApp: select traveler listing + request
  MobileApp->>ApiClient: createMatch(listingID, requestID)
  ApiClient->>Backend: POST /v1/matches
  Backend->>Backend: authRequired(roleAny)
  Backend->>Repo: CreateMatch(match)
  Repo->>Database: insert match row
  Database-->>Repo: match created
  Repo-->>Backend: match
  Backend-->>ApiClient: match response
```

### 3.4 Escrow Creation and Payment Hold

```mermaid
sequenceDiagram
  participant Client
  participant MobileApp
  participant ApiClient
  participant Backend
  participant Repo
  participant PaymentProvider
  participant Database

  Client->>MobileApp: initiate escrow for match
  MobileApp->>ApiClient: createEscrow(matchID, amount)
  ApiClient->>Backend: POST /v1/escrows
  Backend->>Backend: authRequired(roleClientOrAdmin)
  Backend->>Repo: CreateEscrow(matchID, currency, amount, commissionRate)
  Repo->>Database: insert escrow row
  Database-->>Repo: escrow created
  Repo-->>Backend: escrow
  Backend->>PaymentProvider: CreateEscrowHold(EscrowHoldRequest)
  PaymentProvider-->>Backend: hold result
  Backend-->>ApiClient: escrow response
  ApiClient-->>MobileApp: escrow created + payment held
```

### 3.5 KYC Submission and Admin Review

```mermaid
sequenceDiagram
  participant Traveler
  participant MobileApp
  participant ApiClient
  participant Backend
  participant Repo
  participant Database
  participant Admin

  Traveler->>MobileApp: submit KYC documents
  MobileApp->>ApiClient: submitKYC(document data)
  ApiClient->>Backend: POST /v1/kyc/verifications
  Backend->>Backend: authRequired(roleAny)
  Backend->>Repo: CreateKYCVerification(kyc)
  Repo->>Database: insert kyc_verification row
  Database-->>Repo: kyc created
  Repo-->>Backend: kyc verification
  Backend-->>ApiClient: KYC response

  Admin->>MobileApp: open admin KYC queue
  MobileApp->>ApiClient: adminKYC(status="pending")
  ApiClient->>Backend: GET /v1/admin/kyc/verifications?status=pending
  Backend->>Repo: ListKYCVerifications(status="pending", userID="")
  Repo->>Database: query pending KYC rows
  Database-->>Repo: pending list
  Repo-->>Backend: results
  Backend-->>ApiClient: pending KYC list
  Admin->>MobileApp: approve/reject KYC
  MobileApp->>ApiClient: adminReviewKYC(id, status, notes)
  ApiClient->>Backend: POST /v1/admin/kyc/verifications/{id}/review
  Backend->>Backend: authRequired(roleAdminOnly)
  Backend->>Repo: ReviewKYCVerification(id, status, notes)
  Repo->>Database: update kyc row
  Database-->>Repo: updated verification
  Repo-->>Backend: review result
  Backend-->>ApiClient: updated KYC status
```

## 4. Notes d’analyse

- `backend/internal/domain/models.go` contient les entités principales du domaine : `User`, `TravelerListing`, `DeliveryRequest`, `Match`, `Escrow`, `KYCVerification`, `PackageVerification`, `TrackingEvent`.
- `backend/internal/http/server.go` expose toutes les routes REST et orchestre l’authentification, les validations et les appels au dépôt (`store.Repository`).
- `backend/internal/store/repository.go` définit l’interface de persistance. Les implémentations actuelles sont en mémoire (`memory.go`) et Postgres (`postgres.go`).
- `backend/internal/auth/jwt.go` gère l’émission et la validation des tokens JWT.
- `mobile/lib/src/api/api_client.dart` contient le client API utilisé par l’application Flutter et simule un mode démo si l’API réelle n’est pas disponible.
- Le front Flutter sépare l’écran d’authentification (`AuthScreen`), le tableau de bord principal (`HomeScreen`), et des écrans métier comme les listes, KYC, vérifications de colis et admin.
- Les flux critiques sont : inscription/authentification, publication d’annonces/ demandes, appariement, escrows/payments, verifications KYC/colis, suivi des livraisons.

## 5. Fichiers clés

- `backend/internal/http/server.go`
- `backend/internal/domain/models.go`
- `backend/internal/store/repository.go`
- `backend/internal/auth/jwt.go`
- `mobile/lib/src/api/api_client.dart`
- `mobile/lib/src/app.dart`
- `mobile/lib/src/features/home/home_screen.dart`
