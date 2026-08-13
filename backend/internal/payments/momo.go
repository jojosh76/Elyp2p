package payments

import (
	"errors"
	"strings"
	"time"
)

// MomoProvider is a lightweight adapter for Mobile Money (MoMo).
// This implementation is intentionally minimal and acts as a bridge
// where real HTTP calls to a payment gateway would be implemented.
type MomoProvider struct {
	apiKey string
	secret string
}

func NewMomoProvider(apiKey, secret string) (*MomoProvider, error) {
	return &MomoProvider{apiKey: apiKey, secret: secret}, nil
}

func (p *MomoProvider) Name() string { return "momo" }

func (p *MomoProvider) CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	// In a production provider we'd call the MoMo API to create a payment hold.
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "momo_hold_" + req.EscrowID,
		Status:    "held",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *MomoProvider) ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	// In production, call MoMo payout API
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "momo_payout_" + req.EscrowID,
		Status:    "queued",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *MomoProvider) RefundEscrow(req EscrowRefundRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "momo_refund_" + req.EscrowID,
		Status:    "refunded",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *MomoProvider) EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error) {
	if strings.TrimSpace(req.UserID) == "" {
		return PayoutAccountResult{}, errors.New("user id is required")
	}
	return PayoutAccountResult{Provider: p.Name(), AccountID: "momo_acct_" + req.UserID, Status: "created"}, nil
}

func (p *MomoProvider) CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error) {
	if strings.TrimSpace(req.AccountID) == "" {
		return PayoutOnboardingLinkResult{}, errors.New("account id is required")
	}
	// No real onboarding flow; return a placeholder URL
	return PayoutOnboardingLinkResult{URL: "https://example.test/momo/onboard/" + req.AccountID}, nil
}

func (p *MomoProvider) ParseWebhook(payload []byte, _ string) (WebhookEvent, error) {
	// No real webhook parsing implemented for minimal provider.
	return WebhookEvent{}, errors.New("webhook not implemented for momo provider")
}
