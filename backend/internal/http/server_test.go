package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"p2p-delivery/backend/internal/auth"
	"p2p-delivery/backend/internal/domain"
	"p2p-delivery/backend/internal/store"

	"golang.org/x/crypto/bcrypt"
)

func TestSecurityHeadersAreApplied(t *testing.T) {
	srv, _, _ := newTestServer(5, 5)
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rr := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rr, req)
	if got := rr.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("expected nosniff header, got %q", got)
	}
	if got := rr.Header().Get("X-Frame-Options"); got != "DENY" {
		t.Fatalf("expected frame options header, got %q", got)
	}
	if got := rr.Header().Get("Content-Security-Policy"); got == "" {
		t.Fatalf("expected CSP header")
	}
}

func TestAuthEndpointsAreRateLimited(t *testing.T) {
	srv, _, _ := newTestServer(5, 5)
	body := map[string]any{"email": "someone@example.com", "password": "bad-pass"}
	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	var lastCode int
	for i := 0; i < 25; i++ {
		req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", bytes.NewReader(payload))
		req.Header.Set("Content-Type", "application/json")
		rr := httptest.NewRecorder()
		srv.Handler().ServeHTTP(rr, req)
		lastCode = rr.Code
	}
	if lastCode != http.StatusTooManyRequests {
		t.Fatalf("expected 429 after exceeding rate limit, got %d", lastCode)
	}
}

func TestAdminEndpointDeniedForClient(t *testing.T) {
	srv, repo, am := newTestServer(5, 5)
	client := mustCreateUser(t, repo, domain.User{
		Email:        "client1@test.local",
		FullName:     "Client One",
		Role:         domain.RoleClient,
		PasswordHash: mustHash(t, "Client#12345"),
		KYCStatus:    "unverified",
		Phone:        "+14155550111",
	})
	token, err := am.Issue(client.ID, client.Role)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/v1/admin/users", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", rr.Code, rr.Body.String())
	}
}

func TestRegisterAdminEmailIsPromotedToAdmin(t *testing.T) {
	srv, _, am := newTestServer(2, 2)
	body := map[string]any{
		"email":                "admin@adminelysian.com",
		"password":             "Admin#12345",
		"full_name":            "Admin User",
		"role":                 "client",
		"phone":                "+14155550100",
		"permanent_address":    "1 Admin Street",
		"passport_number":      "A1234567",
		"country_of_residence": "US",
	}
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201 got %d body=%s", rr.Code, rr.Body.String())
	}
	var out struct {
		User  domain.User `json:"user"`
		Token string      `json:"token"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if out.User.Role != domain.RoleAdmin {
		t.Fatalf("expected role admin from admin email, got %s", out.User.Role)
	}
	if _, err := am.Parse(out.Token); err != nil {
		t.Fatalf("expected valid token for admin user: %v", err)
	}
	assertStatus(t, srv, http.MethodGet, "/v1/admin/users", out.Token, nil, http.StatusOK)
}

func TestLoginAndOTPLockouts(t *testing.T) {
	srv, repo, _ := newTestServer(2, 2)
	client := mustCreateUser(t, repo, domain.User{
		Email:        "client2@test.local",
		FullName:     "Client Two",
		Role:         domain.RoleClient,
		PasswordHash: mustHash(t, "Client#12345"),
		KYCStatus:    "unverified",
		Phone:        "+14155550112",
	})

	loginBody := map[string]any{"email": client.Email, "password": "wrong"}
	assertStatus(t, srv, http.MethodPost, "/v1/auth/login", "", loginBody, http.StatusUnauthorized)
	assertStatus(t, srv, http.MethodPost, "/v1/auth/login", "", loginBody, http.StatusUnauthorized)
	assertStatus(t, srv, http.MethodPost, "/v1/auth/login", "", loginBody, http.StatusTooManyRequests)

	sessionID, err := repo.CreateOTPChallenge(client.ID, client.Phone, "login", "222222", time.Now().UTC().Add(5*time.Minute))
	if err != nil {
		t.Fatalf("create otp challenge: %v", err)
	}
	otpBody := map[string]any{"otp_session_id": sessionID, "otp_code": "111111"}
	assertStatus(t, srv, http.MethodPost, "/v1/auth/otp/verify", "", otpBody, http.StatusUnauthorized)
	assertStatus(t, srv, http.MethodPost, "/v1/auth/otp/verify", "", otpBody, http.StatusUnauthorized)
	assertStatus(t, srv, http.MethodPost, "/v1/auth/otp/verify", "", otpBody, http.StatusTooManyRequests)
}

func TestEscrowLifecycleActions(t *testing.T) {
	srv, repo, am := newTestServer(5, 5)
	traveler := mustCreateUser(t, repo, domain.User{
		Email:              "traveler@test.local",
		FullName:           "Traveler",
		Role:               domain.RoleTraveler,
		PasswordHash:       mustHash(t, "Traveler#12345"),
		KYCStatus:          "verified",
		Phone:              "+14155550113",
		PermanentAddress:   "123 Test Ave",
		PassportNumber:     "X1234567",
		CountryOfResidence: "US",
	})
	client := mustCreateUser(t, repo, domain.User{
		Email:        "client3@test.local",
		FullName:     "Client Three",
		Role:         domain.RoleClient,
		PasswordHash: mustHash(t, "Client#12345"),
		KYCStatus:    "unverified",
		Phone:        "+14155550114",
	})
	clientToken, err := am.Issue(client.ID, client.Role)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	now := time.Now().UTC()
	listing, err := repo.CreateTravelerListing(domain.TravelerListing{
		TravelerID:      traveler.ID,
		Origin:          "NYC",
		DestinationType: domain.DestinationCity,
		Destination:     "LON",
		DepartureDate:   now.Add(24 * time.Hour),
		ArrivalDate:     now.Add(48 * time.Hour),
		MaxWeightKg:     10,
		PricePerKg:      15,
	})
	if err != nil {
		t.Fatalf("create listing: %v", err)
	}
	request, err := repo.CreateDeliveryRequest(domain.DeliveryRequest{
		ClientID:           client.ID,
		Origin:             "NYC",
		DestinationType:    domain.DestinationCity,
		Destination:        "LON",
		WeightKg:           2,
		PackageDescription: "Docs",
		DeclaredValue:      50,
	})
	if err != nil {
		t.Fatalf("create request: %v", err)
	}
	pkg, err := repo.CreatePackageVerification(domain.PackageVerification{
		RequestID:        request.ID,
		DeclaredContents: "Documents",
		ReceiptRef:       "receipt-1",
		ScreeningMethod:  "manual",
		RiskScore:        10,
	})
	if err != nil {
		t.Fatalf("create package verification: %v", err)
	}
	if _, err := repo.ReviewPackageVerification(pkg.ID, "approved", "ok"); err != nil {
		t.Fatalf("review package verification: %v", err)
	}
	match, err := repo.CreateMatch(domain.Match{
		ListingID:   listing.ID,
		RequestID:   request.ID,
		AgreedPrice: 100,
	})
	if err != nil {
		t.Fatalf("create match: %v", err)
	}
	escrow, err := repo.CreateEscrow(match.ID, "USD", 100, 0.10)
	if err != nil {
		t.Fatalf("create escrow: %v", err)
	}

	assertStatus(t, srv, http.MethodPost, "/v1/escrows/"+escrow.ID+"/release", clientToken, nil, http.StatusBadRequest)
	assertStatus(t, srv, http.MethodPost, "/v1/escrows/"+escrow.ID+"/fund", clientToken, nil, http.StatusOK)
	assertStatus(t, srv, http.MethodPost, "/v1/escrows/"+escrow.ID+"/dispute", clientToken, nil, http.StatusOK)
	assertStatus(t, srv, http.MethodPost, "/v1/escrows/"+escrow.ID+"/refund", clientToken, nil, http.StatusOK)
}

func TestRecommendListingsForRequestReturnsScoreAndSuggestedPrice(t *testing.T) {
	srv, repo, am := newTestServer(5, 5)
	traveler := mustCreateUser(t, repo, domain.User{
		Email:              "traveler-rec@test.local",
		FullName:           "Recommendation Traveler",
		Role:               domain.RoleTraveler,
		PasswordHash:       mustHash(t, "Traveler#12345"),
		KYCStatus:          "verified",
		Phone:              "+14155550116",
		PermanentAddress:   "123 Test Ave",
		PassportNumber:     "X1234568",
		CountryOfResidence: "US",
	})
	client := mustCreateUser(t, repo, domain.User{
		Email:        "client-rec@test.local",
		FullName:     "Recommendation Client",
		Role:         domain.RoleClient,
		PasswordHash: mustHash(t, "Client#12345"),
		KYCStatus:    "unverified",
		Phone:        "+14155550117",
	})
	token, err := am.Issue(client.ID, client.Role)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	now := time.Now().UTC()
	_, err = repo.CreateTravelerListing(domain.TravelerListing{
		TravelerID:      traveler.ID,
		Origin:          "Paris",
		DestinationType: domain.DestinationCity,
		Destination:     "Lagos",
		DepartureDate:   now.Add(24 * time.Hour),
		ArrivalDate:     now.Add(48 * time.Hour),
		MaxWeightKg:     5,
		PricePerKg:      12,
	})
	if err != nil {
		t.Fatalf("create listing: %v", err)
	}
	request, err := repo.CreateDeliveryRequest(domain.DeliveryRequest{
		ClientID:           client.ID,
		Origin:             "Paris",
		DestinationType:    domain.DestinationCity,
		Destination:        "Lagos",
		RecipientName:      "Recipient",
		RecipientPhone:     "+2348012345678",
		DropoffAddress:     "Lagos Island",
		WeightKg:           2,
		PackageDescription: "Phone accessories",
		DeclaredValue:      180,
	})
	if err != nil {
		t.Fatalf("create request: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/v1/recommendations/listings?request_id="+request.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rr := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 got %d body=%s", rr.Code, rr.Body.String())
	}
	var out []struct {
		Score          int     `json:"score"`
		SuggestedPrice float64 `json:"suggested_price"`
		Feasible       bool    `json:"feasible"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(out) != 1 {
		t.Fatalf("expected one recommendation, got %d", len(out))
	}
	if !out[0].Feasible || out[0].Score < 80 {
		t.Fatalf("expected high feasible score, got %+v", out[0])
	}
	if out[0].SuggestedPrice <= 24 {
		t.Fatalf("expected dynamic price above base, got %.2f", out[0].SuggestedPrice)
	}
}

func TestLogoutRevokesToken(t *testing.T) {
	srv, repo, am := newTestServer(5, 5)
	user := mustCreateUser(t, repo, domain.User{
		Email:        "client4@test.local",
		FullName:     "Client Four",
		Role:         domain.RoleClient,
		PasswordHash: mustHash(t, "Client#12345"),
		KYCStatus:    "unverified",
		Phone:        "+14155550115",
	})
	token, err := am.Issue(user.ID, user.Role)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	assertStatus(t, srv, http.MethodPost, "/v1/auth/logout", token, nil, http.StatusOK)
	assertStatus(t, srv, http.MethodGet, "/v1/me", token, nil, http.StatusUnauthorized)
}

func newTestServer(authMaxFails, otpMaxFails int) (*Server, store.Repository, *auth.Manager) {
	repo := store.NewMemoryStore()
	am := auth.NewManager("test-secret", time.Hour)
	srv := NewServer(
		repo,
		am,
		0.10,
		5*time.Minute,
		true,
		"",
		"",
		"",
		"upload-secret",
		"test_uploads",
		10*time.Minute,
		authMaxFails,
		time.Hour,
		otpMaxFails,
		time.Hour,
	)
	return srv, repo, am
}

func mustHash(t *testing.T, in string) string {
	t.Helper()
	out, err := bcrypt.GenerateFromPassword([]byte(in), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	return string(out)
}

func mustCreateUser(t *testing.T, repo store.Repository, u domain.User) domain.User {
	t.Helper()
	out, err := repo.CreateUser(u)
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	return out
}

func assertStatus(t *testing.T, srv *Server, method, path, token string, body map[string]any, want int) {
	t.Helper()
	var reader *bytes.Reader
	if body == nil {
		reader = bytes.NewReader(nil)
	} else {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		reader = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rr, req)
	if rr.Code != want {
		t.Fatalf("request %s %s expected %d got %d body=%s", method, path, want, rr.Code, rr.Body.String())
	}
}
