package payments

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

type NoopProvider struct{}

func NewNoopProvider() *NoopProvider {
	return &NoopProvider{}
}

func (p *NoopProvider) Name() string { return "noop" }

func (p *NoopProvider) CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "noop_hold_" + req.EscrowID,
		Status:    "held",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *NoopProvider) ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "noop_payout_" + req.EscrowID,
		Status:    "queued",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *NoopProvider) RefundEscrow(req EscrowRefundRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: "noop_refund_" + req.EscrowID,
		Status:    "refunded",
		Raw:       "{}",
		At:        time.Now().UTC(),
	}, nil
}

func (p *NoopProvider) EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error) {
	if strings.TrimSpace(req.UserID) == "" {
		return PayoutAccountResult{}, errors.New("user id is required")
	}
	return PayoutAccountResult{
		Provider:  p.Name(),
		AccountID: "noop_acct_" + req.UserID,
		Status:    "pending_onboarding",
	}, nil
}

func (p *NoopProvider) CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error) {
	if strings.TrimSpace(req.AccountID) == "" {
		return PayoutOnboardingLinkResult{}, errors.New("account id is required")
	}
	return PayoutOnboardingLinkResult{
		URL: "https://example.test/noop/onboarding/" + req.AccountID,
	}, nil
}

func (p *NoopProvider) ParseWebhook(payload []byte, _ string) (WebhookEvent, error) {
	trimmed := strings.TrimSpace(string(payload))
	if trimmed == "" {
		return WebhookEvent{}, errors.New("empty payload")
	}
	var in struct {
		EventID   string `json:"event_id"`
		Type      string `json:"type"`
		EscrowID  string `json:"escrow_id"`
		Reference string `json:"reference"`
		Status    string `json:"status"`
	}
	_ = json.Unmarshal(payload, &in)
	eventID := strings.TrimSpace(in.EventID)
	if eventID == "" {
		sum := sha256.Sum256(payload)
		eventID = hex.EncodeToString(sum[:])
	}
	eventType := strings.TrimSpace(in.Type)
	if eventType == "" {
		eventType = "noop.event"
	}
	return WebhookEvent{
		Provider:        p.Name(),
		ProviderEventID: eventID,
		EventType:       eventType,
		EscrowID:        strings.TrimSpace(in.EscrowID),
		Reference:       strings.TrimSpace(in.Reference),
		Status:          strings.TrimSpace(in.Status),
		Payload:         string(payload),
	}, nil
}
