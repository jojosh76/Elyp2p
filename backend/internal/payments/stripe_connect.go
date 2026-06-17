package payments

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type StripeConnectProvider struct {
	secretKey            string
	webhookSecret        string
	refreshURL           string
	returnURL            string
	defaultPaymentMethod string
	apiBase              string
	client               *http.Client
}

func NewStripeConnectProvider(secretKey, webhookSecret, refreshURL, returnURL, defaultPaymentMethod string) (*StripeConnectProvider, error) {
	secretKey = strings.TrimSpace(secretKey)
	if secretKey == "" {
		return nil, errors.New("stripe secret key is required")
	}
	return &StripeConnectProvider{
		secretKey:            secretKey,
		webhookSecret:        strings.TrimSpace(webhookSecret),
		refreshURL:           strings.TrimSpace(refreshURL),
		returnURL:            strings.TrimSpace(returnURL),
		defaultPaymentMethod: strings.TrimSpace(defaultPaymentMethod),
		apiBase:              "https://api.stripe.com/v1",
		client:               &http.Client{Timeout: 20 * time.Second},
	}, nil
}

func (p *StripeConnectProvider) Name() string { return "stripe_connect" }

func (p *StripeConnectProvider) CreateEscrowHold(req EscrowHoldRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	amountMinor, err := toMinorAmount(req.Amount)
	if err != nil {
		return ProviderResult{}, err
	}
	currency := strings.ToLower(strings.TrimSpace(req.Currency))
	if currency == "" {
		currency = "usd"
	}
	paymentMethod := strings.TrimSpace(p.defaultPaymentMethod)
	if paymentMethod == "" {
		return ProviderResult{}, errors.New("stripe payment method is required (set STRIPE_DEFAULT_PAYMENT_METHOD or pass payment method from app)")
	}
	form := url.Values{}
	form.Set("amount", strconv.FormatInt(amountMinor, 10))
	form.Set("currency", currency)
	form.Set("capture_method", "manual")
	form.Set("confirm", "true")
	form.Set("payment_method", paymentMethod)
	form.Set("confirmation_method", "automatic")
	form.Set("metadata[escrow_id]", req.EscrowID)
	form.Set("metadata[action]", "fund")
	form.Set("description", "Escrow hold "+req.EscrowID)
	respBody, err := p.stripeFormRequest(http.MethodPost, "/payment_intents", form, req.IdempotencyKey)
	if err != nil {
		return ProviderResult{}, err
	}
	var out struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return ProviderResult{}, errors.New("failed to decode stripe payment intent response")
	}
	if strings.TrimSpace(out.ID) == "" {
		return ProviderResult{}, errors.New("stripe returned empty payment_intent id")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: out.ID,
		Status:    strings.TrimSpace(out.Status),
		Raw:       string(respBody),
		At:        time.Now().UTC(),
	}, nil
}

func (p *StripeConnectProvider) ReleasePayout(req EscrowPayoutRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	if strings.TrimSpace(req.TravelerAccountID) == "" {
		return ProviderResult{}, errors.New("traveler connected account is required")
	}
	amountMinor, err := toMinorAmount(req.Amount)
	if err != nil {
		return ProviderResult{}, err
	}
	currency := strings.ToLower(strings.TrimSpace(req.Currency))
	if currency == "" {
		currency = "usd"
	}
	paymentIntentID := strings.TrimSpace(req.HoldReference)
	if !strings.HasPrefix(paymentIntentID, "pi_") {
		return ProviderResult{}, errors.New("invalid hold reference for stripe capture")
	}
	captureForm := url.Values{}
	captureForm.Set("amount_to_capture", strconv.FormatInt(amountMinor, 10))
	captureForm.Set("metadata[escrow_id]", req.EscrowID)
	captureBody, err := p.stripeFormRequest(http.MethodPost, "/payment_intents/"+paymentIntentID+"/capture", captureForm, req.IdempotencyKey+":capture")
	if err != nil {
		return ProviderResult{}, err
	}
	var capture struct {
		ID      string `json:"id"`
		Status  string `json:"status"`
		Charges struct {
			Data []struct {
				ID string `json:"id"`
			} `json:"data"`
		} `json:"charges"`
	}
	if err := json.Unmarshal(captureBody, &capture); err != nil {
		return ProviderResult{}, errors.New("failed to decode stripe capture response")
	}
	if len(capture.Charges.Data) == 0 || strings.TrimSpace(capture.Charges.Data[0].ID) == "" {
		return ProviderResult{}, errors.New("stripe capture missing charge id for transfer")
	}
	transferForm := url.Values{}
	transferForm.Set("amount", strconv.FormatInt(amountMinor, 10))
	transferForm.Set("currency", currency)
	transferForm.Set("destination", strings.TrimSpace(req.TravelerAccountID))
	transferForm.Set("source_transaction", capture.Charges.Data[0].ID)
	transferForm.Set("transfer_group", "escrow:"+req.EscrowID)
	transferForm.Set("metadata[escrow_id]", req.EscrowID)
	transferBody, err := p.stripeFormRequest(http.MethodPost, "/transfers", transferForm, req.IdempotencyKey+":transfer")
	if err != nil {
		return ProviderResult{}, err
	}
	var transfer struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(transferBody, &transfer); err != nil {
		return ProviderResult{}, errors.New("failed to decode stripe transfer response")
	}
	if strings.TrimSpace(transfer.ID) == "" {
		return ProviderResult{}, errors.New("stripe transfer id is empty")
	}
	return ProviderResult{
		Provider:  p.Name(),
		Reference: transfer.ID,
		Status:    "payout_queued",
		Raw:       string(transferBody),
		At:        time.Now().UTC(),
	}, nil
}

func (p *StripeConnectProvider) RefundEscrow(req EscrowRefundRequest) (ProviderResult, error) {
	if strings.TrimSpace(req.EscrowID) == "" {
		return ProviderResult{}, errors.New("escrow id is required")
	}
	amountMinor, err := toMinorAmount(req.Amount)
	if err != nil {
		return ProviderResult{}, err
	}
	reference := strings.TrimSpace(req.HoldReference)
	switch {
	case strings.HasPrefix(reference, "pi_"):
		form := url.Values{}
		form.Set("payment_intent", reference)
		form.Set("amount", strconv.FormatInt(amountMinor, 10))
		form.Set("metadata[escrow_id]", req.EscrowID)
		body, err := p.stripeFormRequest(http.MethodPost, "/refunds", form, req.IdempotencyKey+":refund")
		if err != nil {
			return ProviderResult{}, err
		}
		var out struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		}
		if err := json.Unmarshal(body, &out); err != nil {
			return ProviderResult{}, errors.New("failed to decode stripe refund response")
		}
		return ProviderResult{
			Provider:  p.Name(),
			Reference: out.ID,
			Status:    "refunded_" + strings.TrimSpace(out.Status),
			Raw:       string(body),
			At:        time.Now().UTC(),
		}, nil
	case strings.HasPrefix(reference, "tr_"):
		form := url.Values{}
		form.Set("amount", strconv.FormatInt(amountMinor, 10))
		form.Set("metadata[escrow_id]", req.EscrowID)
		body, err := p.stripeFormRequest(http.MethodPost, "/transfers/"+reference+"/reversals", form, req.IdempotencyKey+":reversal")
		if err != nil {
			return ProviderResult{}, err
		}
		var out struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		}
		if err := json.Unmarshal(body, &out); err != nil {
			return ProviderResult{}, errors.New("failed to decode stripe reversal response")
		}
		return ProviderResult{
			Provider:  p.Name(),
			Reference: out.ID,
			Status:    "reversed_" + strings.TrimSpace(out.Status),
			Raw:       string(body),
			At:        time.Now().UTC(),
		}, nil
	default:
		return ProviderResult{}, errors.New("hold reference must be stripe payment_intent (pi_) or transfer (tr_)")
	}
}

func (p *StripeConnectProvider) EnsurePayoutAccount(req PayoutAccountRequest) (PayoutAccountResult, error) {
	if strings.TrimSpace(req.UserID) == "" {
		return PayoutAccountResult{}, errors.New("user id is required")
	}
	email := strings.TrimSpace(req.Email)
	if email == "" {
		return PayoutAccountResult{}, errors.New("email is required")
	}
	country := strings.ToUpper(strings.TrimSpace(req.Country))
	if country == "" {
		country = "US"
	}
	business := strings.ToLower(strings.TrimSpace(req.Business))
	if business == "" {
		business = "individual"
	}
	form := url.Values{}
	form.Set("type", "express")
	form.Set("country", country)
	form.Set("email", email)
	form.Set("business_type", business)
	form.Set("capabilities[transfers][requested]", "true")
	form.Set("metadata[user_id]", req.UserID)
	body, err := p.stripeFormRequest(http.MethodPost, "/accounts", form, "acct:"+req.UserID)
	if err != nil {
		return PayoutAccountResult{}, err
	}
	var out struct {
		ID               string `json:"id"`
		ChargesEnabled   bool   `json:"charges_enabled"`
		PayoutsEnabled   bool   `json:"payouts_enabled"`
		DetailsSubmitted bool   `json:"details_submitted"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return PayoutAccountResult{}, errors.New("failed to decode stripe account response")
	}
	status := "pending_onboarding"
	if out.DetailsSubmitted {
		status = "details_submitted"
	}
	if out.PayoutsEnabled || out.ChargesEnabled {
		status = "enabled"
	}
	return PayoutAccountResult{
		Provider:  p.Name(),
		AccountID: strings.TrimSpace(out.ID),
		Status:    status,
	}, nil
}

func (p *StripeConnectProvider) CreatePayoutOnboardingLink(req PayoutOnboardingLinkRequest) (PayoutOnboardingLinkResult, error) {
	if strings.TrimSpace(req.AccountID) == "" {
		return PayoutOnboardingLinkResult{}, errors.New("account id is required")
	}
	refreshURL := strings.TrimSpace(req.RefreshURL)
	returnURL := strings.TrimSpace(req.ReturnURL)
	if refreshURL == "" {
		refreshURL = p.refreshURL
	}
	if returnURL == "" {
		returnURL = p.returnURL
	}
	if refreshURL == "" || returnURL == "" {
		return PayoutOnboardingLinkResult{}, errors.New("refresh_url and return_url are required")
	}
	form := url.Values{}
	form.Set("account", req.AccountID)
	form.Set("type", "account_onboarding")
	form.Set("refresh_url", refreshURL)
	form.Set("return_url", returnURL)
	body, err := p.stripeFormRequest(http.MethodPost, "/account_links", form, "acctlink:"+req.AccountID)
	if err != nil {
		return PayoutOnboardingLinkResult{}, err
	}
	var out struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return PayoutOnboardingLinkResult{}, errors.New("failed to decode stripe account link response")
	}
	if strings.TrimSpace(out.URL) == "" {
		return PayoutOnboardingLinkResult{}, errors.New("stripe account link url is empty")
	}
	return PayoutOnboardingLinkResult{URL: out.URL}, nil
}

func (p *StripeConnectProvider) ParseWebhook(payload []byte, signature string) (WebhookEvent, error) {
	if len(payload) == 0 {
		return WebhookEvent{}, errors.New("empty payload")
	}
	if strings.TrimSpace(p.webhookSecret) == "" {
		return WebhookEvent{}, errors.New("stripe webhook secret is not configured")
	}
	if err := verifyStripeSignature(payload, signature, p.webhookSecret); err != nil {
		return WebhookEvent{}, err
	}
	var evt struct {
		ID   string `json:"id"`
		Type string `json:"type"`
		Data struct {
			Object map[string]any `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &evt); err != nil {
		return WebhookEvent{}, errors.New("invalid stripe webhook payload")
	}
	reference := getMapString(evt.Data.Object, "id")
	status := strings.TrimSpace(getMapString(evt.Data.Object, "status"))
	escrowID := ""
	if md, ok := evt.Data.Object["metadata"].(map[string]any); ok {
		escrowID = strings.TrimSpace(getMapString(md, "escrow_id"))
	}
	if status == "" && strings.HasPrefix(evt.Type, "transfer.") {
		status = "payout_" + strings.TrimPrefix(evt.Type, "transfer.")
	}
	if status == "" && strings.HasPrefix(evt.Type, "charge.refund") {
		status = "refunded"
	}
	return WebhookEvent{
		Provider:        p.Name(),
		ProviderEventID: strings.TrimSpace(evt.ID),
		EventType:       strings.TrimSpace(evt.Type),
		EscrowID:        escrowID,
		Reference:       reference,
		Status:          status,
		Payload:         string(payload),
	}, nil
}

func (p *StripeConnectProvider) stripeFormRequest(method, path string, form url.Values, idempotencyKey string) ([]byte, error) {
	u := strings.TrimRight(p.apiBase, "/") + path
	req, err := http.NewRequest(method, u, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(p.secretKey, "")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if strings.TrimSpace(idempotencyKey) != "" {
		req.Header.Set("Idempotency-Key", strings.TrimSpace(idempotencyKey))
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("stripe api error (%d): %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return body, nil
}

func verifyStripeSignature(payload []byte, header, secret string) error {
	header = strings.TrimSpace(header)
	secret = strings.TrimSpace(secret)
	if header == "" || secret == "" {
		return errors.New("missing stripe webhook signature")
	}
	parts := strings.Split(header, ",")
	var timestamp string
	var sigs []string
	for _, p := range parts {
		kv := strings.SplitN(strings.TrimSpace(p), "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch strings.TrimSpace(kv[0]) {
		case "t":
			timestamp = strings.TrimSpace(kv[1])
		case "v1":
			sigs = append(sigs, strings.TrimSpace(kv[1]))
		}
	}
	if timestamp == "" || len(sigs) == 0 {
		return errors.New("invalid stripe signature header")
	}
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return errors.New("invalid stripe signature timestamp")
	}
	now := time.Now().UTC().Unix()
	if ts < now-300 || ts > now+300 {
		return errors.New("stripe signature timestamp outside tolerance")
	}
	signedPayload := timestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signedPayload))
	expected := hex.EncodeToString(mac.Sum(nil))
	for _, sig := range sigs {
		if hmac.Equal([]byte(sig), []byte(expected)) {
			return nil
		}
	}
	return errors.New("stripe signature verification failed")
}

func toMinorAmount(amount float64) (int64, error) {
	if amount <= 0 {
		return 0, errors.New("amount must be positive")
	}
	v := int64(math.Round(amount * 100))
	if v <= 0 {
		return 0, errors.New("amount too small")
	}
	return v, nil
}

func getMapString(m map[string]any, key string) string {
	v, ok := m[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	default:
		return fmt.Sprintf("%v", t)
	}
}
