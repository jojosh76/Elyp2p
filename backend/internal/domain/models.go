package domain

import "time"

type DestinationType string

const (
	DestinationCity    DestinationType = "city"
	DestinationCountry DestinationType = "country"
)

type UserRole string

const (
	RoleClient   UserRole = "client"
	RoleTraveler UserRole = "traveler"
	RoleAdmin    UserRole = "admin"
)

type User struct {
	ID                  string    `json:"id"`
	Email               string    `json:"email"`
	FullName            string    `json:"full_name"`
	Role                UserRole  `json:"role"`
	PasswordHash        string    `json:"-"`
	AvatarURL           string    `json:"avatar_url"`
	Phone               string    `json:"phone"`
	Bio                 string    `json:"bio"`
	PermanentAddress    string    `json:"permanent_address"`
	PassportNumber      string    `json:"passport_number"`
	CountryOfResidence  string    `json:"country_of_residence"`
	KYCStatus           string    `json:"kyc_status"`
	PayoutProvider      string    `json:"payout_provider"`
	PayoutAccountID     string    `json:"payout_account_id"`
	PayoutAccountStatus string    `json:"payout_account_status"`
	CreatedAt           time.Time `json:"created_at"`
}

type SocialAccount struct {
	ID             string    `json:"id"`
	UserID         string    `json:"user_id"`
	Provider       string    `json:"provider"`
	ProviderUserID string    `json:"provider_user_id"`
	CreatedAt      time.Time `json:"created_at"`
}

type OAuthProviderConfig struct {
	Provider    string    `json:"provider"`
	Enabled     bool      `json:"enabled"`
	ClientID    string    `json:"client_id"`
	IOSClientID string    `json:"ios_client_id"`
	WebClientID string    `json:"web_client_id"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type TravelerListing struct {
	ID              string          `json:"id"`
	TravelerID      string          `json:"traveler_id"`
	TravelerName    string          `json:"traveler_name,omitempty"`
	TravelerAvatar  string          `json:"traveler_avatar_url,omitempty"`
	Origin          string          `json:"origin"`
	DestinationType DestinationType `json:"destination_type"`
	Destination     string          `json:"destination"`
	DepartureDate   time.Time       `json:"departure_date"`
	ArrivalDate     time.Time       `json:"arrival_date"`
	MaxWeightKg     float64         `json:"max_weight_kg"`
	PricePerKg      float64         `json:"price_per_kg"`
	Status          string          `json:"status"`
	CreatedAt       time.Time       `json:"created_at"`
}

type DeliveryRequest struct {
	ID                  string          `json:"id"`
	ClientID            string          `json:"client_id"`
	ClientName          string          `json:"client_name,omitempty"`
	ClientAvatar        string          `json:"client_avatar_url,omitempty"`
	Origin              string          `json:"origin"`
	DestinationType     DestinationType `json:"destination_type"`
	Destination         string          `json:"destination"`
	RecipientName       string          `json:"recipient_name"`
	RecipientPhone      string          `json:"recipient_phone"`
	RecipientPhotoURL   string          `json:"recipient_photo_url"`
	DropoffAddress      string          `json:"dropoff_address"`
	DropoffInstructions string          `json:"dropoff_instructions"`
	WeightKg            float64         `json:"weight_kg"`
	PackageDescription  string          `json:"package_description"`
	DeclaredValue       float64         `json:"declared_value"`
	Status              string          `json:"status"`
	CreatedAt           time.Time       `json:"created_at"`
}

type Match struct {
	ID                  string     `json:"id"`
	ListingID           string     `json:"listing_id"`
	RequestID           string     `json:"request_id"`
	AgreedPrice         float64    `json:"agreed_price"`
	EstimatedDeliveryAt *time.Time `json:"estimated_delivery_at,omitempty"`
	Status              string     `json:"status"`
	CreatedAt           time.Time  `json:"created_at"`
}

type Escrow struct {
	ID               string     `json:"id"`
	MatchID          string     `json:"match_id"`
	Currency         string     `json:"currency"`
	Amount           float64    `json:"amount"`
	CommissionAmount float64    `json:"commission_amount"`
	TravelerAmount   float64    `json:"traveler_amount"`
	Status           string     `json:"status"`
	FundedAt         *time.Time `json:"funded_at,omitempty"`
	ReleasedAt       *time.Time `json:"released_at,omitempty"`
	PayoutStatus     string     `json:"payout_status,omitempty"`
	PayoutProvider   string     `json:"payout_provider,omitempty"`
	PayoutReference  string     `json:"payout_reference,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

type KYCVerification struct {
	ID                string    `json:"id"`
	UserID            string    `json:"user_id"`
	DocumentType      string    `json:"document_type"`
	DocumentReference string    `json:"document_reference"`
	AddressProofRef   string    `json:"address_proof_ref"`
	Status            string    `json:"status"`
	ReviewNotes       string    `json:"review_notes"`
	CreatedAt         time.Time `json:"created_at"`
}

type PackageVerification struct {
	ID               string    `json:"id"`
	RequestID        string    `json:"request_id"`
	DeclaredContents string    `json:"declared_contents"`
	ReceiptRef       string    `json:"receipt_ref"`
	ScreeningMethod  string    `json:"screening_method"`
	RiskScore        int       `json:"risk_score"`
	Status           string    `json:"status"`
	ReviewNotes      string    `json:"review_notes"`
	CreatedAt        time.Time `json:"created_at"`
}

type TrackingEvent struct {
	ID         string     `json:"id"`
	MatchID    string     `json:"match_id"`
	Status     string     `json:"status"`
	Location   string     `json:"location"`
	Notes      string     `json:"notes"`
	OccurredAt *time.Time `json:"occurred_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

type CommissionSummary struct {
	ReleasedEscrows int     `json:"released_escrows"`
	TotalVolume     float64 `json:"total_volume"`
	TotalCommission float64 `json:"total_commission"`
}

type Notification struct {
	ID        string     `json:"id"`
	UserID    string     `json:"user_id"`
	Title     string     `json:"title"`
	Message   string     `json:"message"`
	Type      string     `json:"type"`
	ReadAt    *time.Time `json:"read_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

type PaymentEvent struct {
	ID              string    `json:"id"`
	Provider        string    `json:"provider"`
	ProviderEventID string    `json:"provider_event_id"`
	EventType       string    `json:"event_type"`
	Payload         string    `json:"payload"`
	CreatedAt       time.Time `json:"created_at"`
}
