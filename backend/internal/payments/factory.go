package payments

import (
	"os"
	"strings"
)

func BuildProvider(name string) (Provider, error) {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "", "noop":
		return NewNoopProvider(), nil
	case "stripe", "stripe_connect", "stripe_connect_stub":
		secret := strings.TrimSpace(os.Getenv("STRIPE_SECRET_KEY"))
		webhookSecret := strings.TrimSpace(os.Getenv("STRIPE_WEBHOOK_SECRET"))
		refreshURL := strings.TrimSpace(os.Getenv("STRIPE_CONNECT_REFRESH_URL"))
		returnURL := strings.TrimSpace(os.Getenv("STRIPE_CONNECT_RETURN_URL"))
		defaultPaymentMethod := strings.TrimSpace(os.Getenv("STRIPE_DEFAULT_PAYMENT_METHOD"))
		provider, err := NewStripeConnectProvider(secret, webhookSecret, refreshURL, returnURL, defaultPaymentMethod)
		if err != nil {
			return nil, err
		}
		return provider, nil
	default:
		return NewNoopProvider(), nil
	}
}

type NamedNoopProvider struct {
	name string
	base *NoopProvider
}

func (p *NamedNoopProvider) ensureBase() *NoopProvider {
	if p.base == nil {
		p.base = NewNoopProvider()
	}
	return p.base
}

func (p *NamedNoopProvider) Name() string {
	if strings.TrimSpace(p.name) == "" {
		return "noop"
	}
	return p.name
}

func (p *NamedNoopProvider) CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error) {
	out, err := p.ensureBase().CreateEscrowHold(req)
	if err != nil {
		return ProviderResult{}, err
	}
	out.Provider = p.Name()
	return out, nil
}

func (p *NamedNoopProvider) ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error) {
	out, err := p.ensureBase().ReleasePayout(req)
	if err != nil {
		return ProviderResult{}, err
	}
	out.Provider = p.Name()
	return out, nil
}

func (p *NamedNoopProvider) RefundEscrow(req EscrowRefundRequest) (ProviderResult, error) {
	out, err := p.ensureBase().RefundEscrow(req)
	if err != nil {
		return ProviderResult{}, err
	}
	out.Provider = p.Name()
	return out, nil
}

func (p *NamedNoopProvider) EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error) {
	out, err := p.ensureBase().EnsurePayoutAccount(req)
	if err != nil {
		return PayoutAccountResult{}, err
	}
	out.Provider = p.Name()
	return out, nil
}

func (p *NamedNoopProvider) CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error) {
	return p.ensureBase().CreatePayoutOnboardingLink(req)
}

func (p *NamedNoopProvider) ParseWebhook(payload []byte, signature string) (WebhookEvent, error) {
	out, err := p.ensureBase().ParseWebhook(payload, signature)
	if err != nil {
		return WebhookEvent{}, err
	}
	out.Provider = p.Name()
	return out, nil
}
