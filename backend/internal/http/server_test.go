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
