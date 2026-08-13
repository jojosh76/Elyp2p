package payments

import (
	"errors"
	"strings"
	"time"
)

// OrangeMoneyProvider is a minimal Orange Money implementation.
type OrangeMoneyProvider struct {
	apiKey string
	secret string
}

func NewOrangeMoneyProvider(apiKey, secret string) (*OrangeMoneyProvider, error) {
	return &OrangeMoneyProvider{apiKey: apiKey, secret: secret}, nil
}

func (p *OrangeMoneyProvider) Name() string { return "orange_money" }

func (p *OrangeMoneyProvider) CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "om_hold_" + req.EscrowID,
		Status:    "held",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *OrangeMoneyProvider) ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "om_payout_" + req.EscrowID,
		Status:    "queued",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *OrangeMoneyProvider) RefundEscrow(req EscrowRefundRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "om_refund_" + req.EscrowID,
		Status:    "refunded",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *OrangeMoneyProvider) EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error) {
	if strings.TrimSpace(req.UserID) == "" {
		return PayoutAccountResult{}, errors.New("user id is required")
	}
	return PayoutAccountResult{Provider: p.Name(), AccountID: "om_acct_" + req.UserID, Status: "created"}, nil
}

func (p *OrangeMoneyProvider) CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error) {
	if strings.TrimSpace(req.AccountID) == "" {
		return PayoutOnboardingLinkResult{}, errors.New("account id is required")
	}
	return PayoutOnboardingLinkResult{URL: "https://example.test/om/onboard/" + req.AccountID}, nil
}

func (p *OrangeMoneyProvider) ParseWebhook(payload []byte, _ string) (WebhookEvent, error) {
	return WebhookEvent{}, errors.New("webhook not implemented for orange money provider")
}
