package store

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"p2p-delivery/backend/internal/domain"
)

type MemoryStore struct {
	mu sync.RWMutex

	seq int64

	usersByID            map[string]domain.User
	userIDByEmail        map[string]string
	socialToUserID       map[string]string
	otpChallenges        map[string]memoryOTPChallenge
	oauthConfigs         map[string]domain.OAuthProviderConfig
	listings             map[string]domain.TravelerListing
	requests             map[string]domain.DeliveryRequest
	matches              map[string]domain.Match
	escrows              map[string]domain.Escrow
	kycVerifications     map[string]domain.KYCVerification
	packageVerifications map[string]domain.PackageVerification
	trackingEvents       map[string][]domain.TrackingEvent
	notifications        map[string]domain.Notification
	paymentEvents        map[string]domain.PaymentEvent
}

type memoryOTPChallenge struct {
	ID         string
	UserID     string
	Phone      string
	Purpose    string
	CodeHash   string
	ExpiresAt  time.Time
	VerifiedAt *time.Time
	CreatedAt  time.Time
}

func NewMemoryStore() *MemoryStore {
	s := &MemoryStore{
		usersByID:            make(map[string]domain.User),
		userIDByEmail:        make(map[string]string),
		socialToUserID:       make(map[string]string),
		otpChallenges:        make(map[string]memoryOTPChallenge),
		oauthConfigs:         make(map[string]domain.OAuthProviderConfig),
		listings:             make(map[string]domain.TravelerListing),
		requests:             make(map[string]domain.DeliveryRequest),
		matches:              make(map[string]domain.Match),
		escrows:              make(map[string]domain.Escrow),
		kycVerifications:     make(map[string]domain.KYCVerification),
		packageVerifications: make(map[string]domain.PackageVerification),
		trackingEvents:       make(map[string][]domain.TrackingEvent),
		notifications:        make(map[string]domain.Notification),
		paymentEvents:        make(map[string]domain.PaymentEvent),
	}
	now := time.Now().UTC()
	s.oauthConfigs["google"] = domain.OAuthProviderConfig{
		Provider:  "google",
		Enabled:   true,
		UpdatedAt: now,
	}
	s.oauthConfigs["apple"] = domain.OAuthProviderConfig{
		Provider:  "apple",
		Enabled:   true,
		UpdatedAt: now,
	}
	return s
}

func (s *MemoryStore) nextID(prefix string) string {
	s.seq++
	return fmt.Sprintf("%s_%d", prefix, s.seq)
}

func (s *MemoryStore) CreateUser(in domain.User) (domain.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	email := strings.ToLower(strings.TrimSpace(in.Email))
	if email == "" {
		return domain.User{}, errors.New("email is required")
	}
	if _, exists := s.userIDByEmail[email]; exists {
		return domain.User{}, errors.New("email already exists")
	}

	in.ID = s.nextID("usr")
	in.Email = email
	in.CreatedAt = time.Now().UTC()
	s.usersByID[in.ID] = in
	s.userIDByEmail[email] = in.ID
	return in, nil
}

func (s *MemoryStore) DeleteUserByID(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	user, ok := s.usersByID[id]
	if !ok {
		return errors.New("user not found")
	}
	delete(s.usersByID, id)
	delete(s.userIDByEmail, strings.ToLower(strings.TrimSpace(user.Email)))
	for key, uid := range s.socialToUserID {
		if uid == id {
			delete(s.socialToUserID, key)
		}
	}
	return nil
}

func (s *MemoryStore) GetUserByEmail(email string) (domain.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	id, ok := s.userIDByEmail[strings.ToLower(strings.TrimSpace(email))]
	if !ok {
		return domain.User{}, errors.New("user not found")
	}
	return s.usersByID[id], nil
}

func (s *MemoryStore) GetUserByID(id string) (domain.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	user, ok := s.usersByID[id]
	if !ok {
		return domain.User{}, errors.New("user not found")
	}
	return user, nil
}

func (s *MemoryStore) ListUsers() ([]domain.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]domain.User, 0, len(s.usersByID))
	for _, u := range s.usersByID {
		out = append(out, u)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

func (s *MemoryStore) UpdateUserProfile(in domain.User) (domain.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.usersByID[in.ID]
	if !ok {
		return domain.User{}, errors.New("user not found")
	}
	existing.FullName = strings.TrimSpace(in.FullName)
	existing.AvatarURL = strings.TrimSpace(in.AvatarURL)
	existing.Phone = strings.TrimSpace(in.Phone)
	existing.Bio = strings.TrimSpace(in.Bio)
	existing.PermanentAddress = strings.TrimSpace(in.PermanentAddress)
	existing.CountryOfResidence = strings.TrimSpace(in.CountryOfResidence)
	s.usersByID[in.ID] = existing
	return existing, nil
}

func (s *MemoryStore) SetUserPayoutAccount(userID, provider, accountID, status string) (domain.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.usersByID[userID]
	if !ok {
		return domain.User{}, errors.New("user not found")
	}
	existing.PayoutProvider = strings.TrimSpace(provider)
	existing.PayoutAccountID = strings.TrimSpace(accountID)
	existing.PayoutAccountStatus = strings.TrimSpace(status)
	s.usersByID[userID] = existing
	return existing, nil
}

func (s *MemoryStore) SocialLogin(provider, providerUserID, email, fullName, avatarURL string) (domain.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	provider = strings.ToLower(strings.TrimSpace(provider))
	providerUserID = strings.TrimSpace(providerUserID)
	email = strings.ToLower(strings.TrimSpace(email))
	if provider == "" || providerUserID == "" || email == "" {
		return domain.User{}, errors.New("provider, provider_user_id and email are required")
	}
	key := provider + ":" + providerUserID
	if userID, ok := s.socialToUserID[key]; ok {
		user := s.usersByID[userID]
		if strings.TrimSpace(avatarURL) != "" {
			user.AvatarURL = strings.TrimSpace(avatarURL)
			s.usersByID[userID] = user
		}
		return user, nil
	}
	if userID, ok := s.userIDByEmail[email]; ok {
		s.socialToUserID[key] = userID
		user := s.usersByID[userID]
		if strings.TrimSpace(avatarURL) != "" {
			user.AvatarURL = strings.TrimSpace(avatarURL)
			s.usersByID[userID] = user
		}
		return user, nil
	}

	user := domain.User{
		ID:        s.nextID("usr"),
		Email:     email,
		FullName:  strings.TrimSpace(fullName),
		AvatarURL: strings.TrimSpace(avatarURL),
		Role:      domain.RoleClient,
		KYCStatus: "unverified",
		CreatedAt: time.Now().UTC(),
	}
	if user.FullName == "" {
		user.FullName = "Social User"
	}
	s.usersByID[user.ID] = user
	s.userIDByEmail[email] = user.ID
	s.socialToUserID[key] = user.ID
	return user, nil
}

func (s *MemoryStore) CreateOTPChallenge(userID, phone, purpose, code string, expiresAt time.Time) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.usersByID[userID]; !ok {
		return "", errors.New("user not found")
	}
	code = strings.TrimSpace(code)
	if code == "" {
		return "", errors.New("otp code is required")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	id := s.nextID("otp")
	s.otpChallenges[id] = memoryOTPChallenge{
		ID:        id,
		UserID:    userID,
		Phone:     strings.TrimSpace(phone),
		Purpose:   strings.TrimSpace(purpose),
		CodeHash:  string(hash),
		ExpiresAt: expiresAt.UTC(),
		CreatedAt: time.Now().UTC(),
	}
	return id, nil
}

func (s *MemoryStore) VerifyOTPChallenge(sessionID, code string) (domain.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	ch, ok := s.otpChallenges[strings.TrimSpace(sessionID)]
	if !ok {
		return domain.User{}, errors.New("otp session not found")
	}
	if ch.VerifiedAt != nil {
		return domain.User{}, errors.New("otp session already used")
	}
	if time.Now().UTC().After(ch.ExpiresAt) {
		return domain.User{}, errors.New("otp code expired")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(ch.CodeHash), []byte(strings.TrimSpace(code))); err != nil {
		return domain.User{}, errors.New("invalid otp code")
	}
	now := time.Now().UTC()
	ch.VerifiedAt = &now
	s.otpChallenges[ch.ID] = ch

	user, ok := s.usersByID[ch.UserID]
	if !ok {
		return domain.User{}, errors.New("user not found")
	}
	return user, nil
}

func (s *MemoryStore) ListOAuthProviderConfigs() ([]domain.OAuthProviderConfig, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := []domain.OAuthProviderConfig{}
	for _, provider := range []string{"google", "apple"} {
		cfg, ok := s.oauthConfigs[provider]
		if !ok {
			cfg = domain.OAuthProviderConfig{
				Provider:  provider,
				Enabled:   true,
				UpdatedAt: time.Now().UTC(),
			}
		}
		out = append(out, cfg)
	}
	return out, nil
}

func (s *MemoryStore) UpsertOAuthProviderConfig(in domain.OAuthProviderConfig) (domain.OAuthProviderConfig, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	provider := strings.ToLower(strings.TrimSpace(in.Provider))
	if provider != "google" && provider != "apple" {
		return domain.OAuthProviderConfig{}, errors.New("provider must be google or apple")
	}
	in.Provider = provider
	in.ClientID = strings.TrimSpace(in.ClientID)
	in.IOSClientID = strings.TrimSpace(in.IOSClientID)
	in.WebClientID = strings.TrimSpace(in.WebClientID)
	in.UpdatedAt = time.Now().UTC()
	s.oauthConfigs[provider] = in
	return in, nil
}

func (s *MemoryStore) CreateTravelerListing(in domain.TravelerListing) (domain.TravelerListing, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	in.ID = s.nextID("lst")
	in.Status = "open"
	in.CreatedAt = time.Now().UTC()
	s.listings[in.ID] = in
	return in, nil
}

func (s *MemoryStore) ListTravelerListings(destination string) ([]domain.TravelerListing, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var out []domain.TravelerListing
	for _, l := range s.listings {
		if destination == "" || strings.EqualFold(destination, l.Destination) {
			out = append(out, l)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

func (s *MemoryStore) ListTravelerListingsByUser(userID string) ([]domain.TravelerListing, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.TravelerListing{}
	for _, l := range s.listings {
		if l.TravelerID == userID {
			out = append(out, l)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) GetTravelerListingByID(id string) (domain.TravelerListing, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out, ok := s.listings[id]
	if !ok {
		return domain.TravelerListing{}, errors.New("listing not found")
	}
	return out, nil
}

func (s *MemoryStore) CreateDeliveryRequest(in domain.DeliveryRequest) (domain.DeliveryRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	in.ID = s.nextID("req")
	in.Status = "open"
	in.CreatedAt = time.Now().UTC()
	s.requests[in.ID] = in
	return in, nil
}

func (s *MemoryStore) ListDeliveryRequests(destination string) ([]domain.DeliveryRequest, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var out []domain.DeliveryRequest
	for _, r := range s.requests {
		if destination == "" || strings.EqualFold(destination, r.Destination) {
			out = append(out, r)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.After(out[j].CreatedAt)
	})
	return out, nil
}

func (s *MemoryStore) ListDeliveryRequestsByUser(userID string) ([]domain.DeliveryRequest, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.DeliveryRequest{}
	for _, r := range s.requests {
		if r.ClientID == userID {
			out = append(out, r)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) GetDeliveryRequestByID(id string) (domain.DeliveryRequest, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out, ok := s.requests[id]
	if !ok {
		return domain.DeliveryRequest{}, errors.New("request not found")
	}
	return out, nil
}

func (s *MemoryStore) CreateMatch(in domain.Match) (domain.Match, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	lst, ok := s.listings[in.ListingID]
	if !ok {
		return domain.Match{}, errors.New("listing not found")
	}
	req, ok := s.requests[in.RequestID]
	if !ok {
		return domain.Match{}, errors.New("request not found")
	}
	if req.WeightKg > lst.MaxWeightKg {
		return domain.Match{}, errors.New("request weight exceeds traveler max weight")
	}

	traveler, ok := s.usersByID[lst.TravelerID]
	if !ok {
		return domain.Match{}, errors.New("traveler not found")
	}
	if traveler.KYCStatus != "verified" {
		return domain.Match{}, errors.New("traveler must be KYC verified before match")
	}
	if !s.requestHasApprovedPackageVerification(req.ID) {
		return domain.Match{}, errors.New("package must pass verification before match")
	}
	for _, m := range s.matches {
		if m.ListingID == in.ListingID && m.RequestID == in.RequestID {
			return domain.Match{}, errors.New("a match already exists for this request and listing")
		}
	}

	in.ID = s.nextID("mat")
	in.Status = "matched"
	in.CreatedAt = time.Now().UTC()
	s.matches[in.ID] = in
	return in, nil
}

func (s *MemoryStore) requestHasApprovedPackageVerification(requestID string) bool {
	for _, p := range s.packageVerifications {
		if p.RequestID == requestID && p.Status == "approved" {
			return true
		}
	}
	return false
}

func (s *MemoryStore) ListMatchesByUser(userID string) ([]domain.Match, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := []domain.Match{}
	for _, m := range s.matches {
		req, reqOK := s.requests[m.RequestID]
		lst, lstOK := s.listings[m.ListingID]
		if !reqOK || !lstOK {
			continue
		}
		if req.ClientID == userID || lst.TravelerID == userID {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) GetMatchByID(id string) (domain.Match, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out, ok := s.matches[id]
	if !ok {
		return domain.Match{}, errors.New("match not found")
	}
	return out, nil
}

func (s *MemoryStore) CreateEscrow(matchID, currency string, amount, commissionRate float64) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.matches[matchID]; !ok {
		return domain.Escrow{}, errors.New("match not found")
	}
	for _, e := range s.escrows {
		if e.MatchID == matchID {
			return domain.Escrow{}, errors.New("escrow already exists for this match")
		}
	}
	commission := amount * commissionRate
	travelerAmount := amount - commission

	out := domain.Escrow{
		ID:               s.nextID("esc"),
		MatchID:          matchID,
		Currency:         currency,
		Amount:           amount,
		CommissionAmount: commission,
		TravelerAmount:   travelerAmount,
		Status:           "pending_funding",
		CreatedAt:        time.Now().UTC(),
	}
	s.escrows[out.ID] = out
	return out, nil
}

func (s *MemoryStore) DeleteEscrowByUser(id, userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.escrows[id]
	if !ok {
		return errors.New("escrow not found")
	}
	m, ok := s.matches[e.MatchID]
	if !ok {
		return errors.New("escrow not found")
	}
	r, rok := s.requests[m.RequestID]
	l, lok := s.listings[m.ListingID]
	if !rok || !lok || (r.ClientID != userID && l.TravelerID != userID) {
		return errors.New("escrow not found")
	}
	delete(s.escrows, id)
	return nil
}

func (s *MemoryStore) FundEscrow(id string) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	if out.Status != "pending_funding" {
		return domain.Escrow{}, errors.New("escrow has already been funded or released")
	}
	now := time.Now().UTC()
	out.Status = "funded"
	out.FundedAt = &now
	s.escrows[id] = out
	return out, nil
}

func (s *MemoryStore) ReleaseEscrow(id string) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	if out.Status != "funded" {
		return domain.Escrow{}, errors.New("escrow must be funded first")
	}
	delivered := false
	for _, ev := range s.trackingEvents[out.MatchID] {
		if strings.EqualFold(strings.TrimSpace(ev.Status), "delivered") {
			delivered = true
			break
		}
	}
	if !delivered {
		return domain.Escrow{}, errors.New("release is locked until tracking status is delivered")
	}
	now := time.Now().UTC()
	out.Status = "released"
	out.ReleasedAt = &now
	s.escrows[id] = out
	return out, nil
}

func (s *MemoryStore) RefundEscrow(id string) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	if out.Status != "funded" && out.Status != "disputed" {
		return domain.Escrow{}, errors.New("only funded or disputed escrow can be refunded")
	}
	out.Status = "refunded"
	s.escrows[id] = out
	return out, nil
}

func (s *MemoryStore) DisputeEscrow(id string) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	if out.Status != "funded" {
		return domain.Escrow{}, errors.New("only funded escrow can be disputed")
	}
	out.Status = "disputed"
	s.escrows[id] = out
	return out, nil
}

func (s *MemoryStore) SetEscrowPayout(id, provider, reference, status string) (domain.Escrow, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	out.PayoutProvider = strings.TrimSpace(provider)
	out.PayoutReference = strings.TrimSpace(reference)
	out.PayoutStatus = strings.TrimSpace(status)
	s.escrows[id] = out
	return out, nil
}

func (s *MemoryStore) ListEscrows() ([]domain.Escrow, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]domain.Escrow, 0, len(s.escrows))
	for _, e := range s.escrows {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) ListEscrowsByUser(userID string) ([]domain.Escrow, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.Escrow{}
	for _, e := range s.escrows {
		m, ok := s.matches[e.MatchID]
		if !ok {
			continue
		}
		r := s.requests[m.RequestID]
		l := s.listings[m.ListingID]
		if r.ClientID == userID || l.TravelerID == userID {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) GetEscrowByID(id string) (domain.Escrow, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out, ok := s.escrows[id]
	if !ok {
		return domain.Escrow{}, errors.New("escrow not found")
	}
	return out, nil
}

func (s *MemoryStore) GetCommissionSummary() (domain.CommissionSummary, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := domain.CommissionSummary{}
	for _, e := range s.escrows {
		if e.Status == "released" {
			out.ReleasedEscrows++
			out.TotalVolume += e.Amount
			out.TotalCommission += e.CommissionAmount
		}
	}
	return out, nil
}

func (s *MemoryStore) CreateKYCVerification(in domain.KYCVerification) (domain.KYCVerification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, k := range s.kycVerifications {
		if k.UserID == in.UserID && (k.Status == "pending_review" || k.Status == "verified") {
			return domain.KYCVerification{}, errors.New("kyc is already submitted for this user")
		}
	}

	in.ID = s.nextID("kyc")
	in.Status = "pending_review"
	in.CreatedAt = time.Now().UTC()
	s.kycVerifications[in.ID] = in
	return in, nil
}

func (s *MemoryStore) ListKYCVerifications(status, userID string) ([]domain.KYCVerification, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.KYCVerification{}
	for _, k := range s.kycVerifications {
		if status != "" && k.Status != status {
			continue
		}
		if userID != "" && k.UserID != userID {
			continue
		}
		out = append(out, k)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) ReviewKYCVerification(id, status, notes string) (domain.KYCVerification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out, ok := s.kycVerifications[id]
	if !ok {
		return domain.KYCVerification{}, errors.New("kyc verification not found")
	}
	if status != "verified" && status != "rejected" {
		return domain.KYCVerification{}, errors.New("status must be verified or rejected")
	}
	out.Status = status
	out.ReviewNotes = notes
	s.kycVerifications[id] = out

	user := s.usersByID[out.UserID]
	user.KYCStatus = status
	s.usersByID[user.ID] = user
	return out, nil
}

func (s *MemoryStore) CreatePackageVerification(in domain.PackageVerification) (domain.PackageVerification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.requests[in.RequestID]; !ok {
		return domain.PackageVerification{}, errors.New("request not found")
	}
	for _, p := range s.packageVerifications {
		if p.RequestID == in.RequestID && (p.Status == "pending_review" || p.Status == "approved") {
			return domain.PackageVerification{}, errors.New("package verification already exists for this request")
		}
	}

	in.ID = s.nextID("pkg")
	in.CreatedAt = time.Now().UTC()
	if in.RiskScore >= 70 {
		in.Status = "rejected_high_risk"
	} else {
		in.Status = "pending_review"
	}
	s.packageVerifications[in.ID] = in
	return in, nil
}

func (s *MemoryStore) ListPackageVerifications(status, requestID string) ([]domain.PackageVerification, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.PackageVerification{}
	for _, p := range s.packageVerifications {
		if status != "" && p.Status != status {
			continue
		}
		if requestID != "" && p.RequestID != requestID {
			continue
		}
		out = append(out, p)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) ReviewPackageVerification(id, status, notes string) (domain.PackageVerification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out, ok := s.packageVerifications[id]
	if !ok {
		return domain.PackageVerification{}, errors.New("package verification not found")
	}
	switch status {
	case "approved", "rejected", "rejected_high_risk":
	default:
		return domain.PackageVerification{}, errors.New("invalid package verification status")
	}
	out.Status = status
	out.ReviewNotes = notes
	s.packageVerifications[id] = out
	return out, nil
}

func (s *MemoryStore) AddTrackingEvent(in domain.TrackingEvent) (domain.TrackingEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.matches[in.MatchID]; !ok {
		return domain.TrackingEvent{}, errors.New("match not found")
	}
	in.ID = s.nextID("trk")
	in.CreatedAt = time.Now().UTC()
	if in.OccurredAt == nil {
		t := in.CreatedAt
		in.OccurredAt = &t
	}
	s.trackingEvents[in.MatchID] = append(s.trackingEvents[in.MatchID], in)
	return in, nil
}

func (s *MemoryStore) ListTrackingEvents(matchID string) ([]domain.TrackingEvent, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	events := s.trackingEvents[matchID]
	out := make([]domain.TrackingEvent, 0, len(events))
	out = append(out, events...)
	sort.Slice(out, func(i, j int) bool {
		return out[i].CreatedAt.Before(out[j].CreatedAt)
	})
	return out, nil
}

func (s *MemoryStore) CreateNotification(in domain.Notification) (domain.Notification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.usersByID[in.UserID]; !ok {
		return domain.Notification{}, errors.New("user not found")
	}
	in.ID = s.nextID("ntf")
	in.CreatedAt = time.Now().UTC()
	s.notifications[in.ID] = in
	return in, nil
}

func (s *MemoryStore) ListNotificationsByUser(userID string) ([]domain.Notification, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := []domain.Notification{}
	for _, n := range s.notifications {
		if n.UserID == userID {
			out = append(out, n)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.After(out[j].CreatedAt) })
	return out, nil
}

func (s *MemoryStore) MarkNotificationRead(id, userID string) (domain.Notification, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	n, ok := s.notifications[id]
	if !ok || n.UserID != userID {
		return domain.Notification{}, errors.New("notification not found")
	}
	now := time.Now().UTC()
	n.ReadAt = &now
	s.notifications[id] = n
	return n, nil
}

func (s *MemoryStore) DeleteNotification(id, userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	n, ok := s.notifications[id]
	if !ok || n.UserID != userID {
		return errors.New("notification not found")
	}
	delete(s.notifications, id)
	return nil
}

func (s *MemoryStore) CreatePaymentEvent(in domain.PaymentEvent) (domain.PaymentEvent, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := strings.TrimSpace(strings.ToLower(in.Provider)) + ":" + strings.TrimSpace(in.ProviderEventID)
	if key == ":" || strings.HasSuffix(key, ":") {
		return domain.PaymentEvent{}, errors.New("provider and provider_event_id are required")
	}
	if existing, ok := s.paymentEvents[key]; ok {
		return existing, errors.New("payment event already exists")
	}
	in.ID = s.nextID("payevt")
	in.CreatedAt = time.Now().UTC()
	s.paymentEvents[key] = in
	return in, nil
}

func (s *MemoryStore) GetPaymentEventByProviderEventID(provider, providerEventID string) (domain.PaymentEvent, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	key := strings.TrimSpace(strings.ToLower(provider)) + ":" + strings.TrimSpace(providerEventID)
	out, ok := s.paymentEvents[key]
	if !ok {
		return domain.PaymentEvent{}, errors.New("payment event not found")
	}
	return out, nil
}
