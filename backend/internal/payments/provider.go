package payments

import "time"

type EscrowPayoutRequest struct {
	EscrowID          string
	TravelerUserID    string
	TravelerAccountID string
	HoldReference     string
	Currency          string
	Amount            float64
	IdempotencyKey    string
}

type EscrowHoldRequest struct {
	EscrowID       string
	ClientUserID   string
	Currency       string
	Amount         float64
	IdempotencyKey string
}

type EscrowRefundRequest struct {
	EscrowID       string
	ClientUserID   string
	HoldReference  string
	Currency       string
	Amount         float64
	IdempotencyKey string
}

type PayoutAccountRequest struct {
	UserID   string
	Email    string
	Country  string
	Business string
}

type PayoutAccountResult struct {
	Provider  string
	AccountID string
	Status    string
}

type PayoutOnboardingLinkRequest struct {
	AccountID  string
	RefreshURL string
	ReturnURL  string
}

type PayoutOnboardingLinkResult struct {
	URL string
}

type ProviderResult struct {
	Provider  string
	Reference string
	Status    string
	Raw       string
	At        time.Time
}

type WebhookEvent struct {
	Provider        string
	ProviderEventID string
	EventType       string
	EscrowID        string
	Reference       string
	Status          string
	Payload         string
}

type Provider interface {
	Name() string
	CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error)
	ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error)
	RefundEscrow(req EscrowRefundRequest) (ProviderResult, error)
	EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error)
	CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error)
	ParseWebhook(payload []byte, signature string) (WebhookEvent, error)
}
