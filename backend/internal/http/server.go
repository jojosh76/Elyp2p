package httpapi

import (
	"context"
	"crypto/hmac"
	cryptorand "crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"p2p-delivery/backend/internal/auth"
	"p2p-delivery/backend/internal/domain"
	"p2p-delivery/backend/internal/payments"
	"p2p-delivery/backend/internal/store"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type contextKey string

const (
	ctxUserIDKey contextKey = "user_id"
	ctxRoleKey   contextKey = "role"
)

type Server struct {
	repo            store.Repository
	authManager     *auth.Manager
	commissionRate  float64
	otpTTL          time.Duration
	otpDevMode      bool
	twilioSID       string
	twilioToken     string
	twilioFrom      string
	uploadSecret    string
	uploadDir       string
	uploadTokenTTL  time.Duration
	authMaxFails    int
	authLockWindow  time.Duration
	otpMaxFails     int
	otpLockWindow   time.Duration
	attemptsMu      sync.Mutex
	loginAttempts   map[string]authAttempt
	otpAttempts     map[string]authAttempt
	revokedTokensMu sync.Mutex
	revokedTokens   map[string]time.Time
	paymentProvider payments.Provider
	mux             *http.ServeMux
}

type authAttempt struct {
	Failures    int
	LockedUntil time.Time
}

func NewServer(
	repo store.Repository,
	authManager *auth.Manager,
	commissionRate float64,
	otpTTL time.Duration,
	otpDevMode bool,
	twilioSID string,
	twilioToken string,
	twilioFrom string,
	uploadSecret string,
	uploadDir string,
	uploadTokenTTL time.Duration,
	authMaxFails int,
	authLockWindow time.Duration,
	otpMaxFails int,
	otpLockWindow time.Duration,
) *Server {
	if authMaxFails <= 0 {
		authMaxFails = 5
	}
	if otpMaxFails <= 0 {
		otpMaxFails = 5
	}
	if authLockWindow <= 0 {
		authLockWindow = 15 * time.Minute
	}
	if otpLockWindow <= 0 {
		otpLockWindow = 15 * time.Minute
	}
	if uploadTokenTTL <= 0 {
		uploadTokenTTL = 15 * time.Minute
	}
	s := &Server{
		repo:            repo,
		authManager:     authManager,
		commissionRate:  commissionRate,
		otpTTL:          otpTTL,
		otpDevMode:      otpDevMode,
		twilioSID:       strings.TrimSpace(twilioSID),
		twilioToken:     strings.TrimSpace(twilioToken),
		twilioFrom:      strings.TrimSpace(twilioFrom),
		uploadSecret:    strings.TrimSpace(uploadSecret),
		uploadDir:       strings.TrimSpace(uploadDir),
		uploadTokenTTL:  uploadTokenTTL,
		authMaxFails:    authMaxFails,
		authLockWindow:  authLockWindow,
		otpMaxFails:     otpMaxFails,
		otpLockWindow:   otpLockWindow,
		loginAttempts:   map[string]authAttempt{},
		otpAttempts:     map[string]authAttempt{},
		paymentProvider: payments.NewNoopProvider(),
		mux:             http.NewServeMux(),
	}
	if s.uploadSecret == "" {
		s.uploadSecret = "insecure-upload-secret"
	}
	if s.uploadDir == "" {
		s.uploadDir = filepath.Join("data", "uploads")
	}
	s.revokedTokens = map[string]time.Time{}
	s.routes()
	return s
}

func (s *Server) Handler() http.Handler {
	return s.mux
}

func (s *Server) SetPaymentProvider(provider payments.Provider) {
	if provider == nil {
		s.paymentProvider = payments.NewNoopProvider()
		return
	}
	s.paymentProvider = provider
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /healthz", s.health)
	s.mux.HandleFunc("POST /v1/auth/register", s.register)
	s.mux.HandleFunc("POST /v1/auth/login", s.login)
	s.mux.HandleFunc("POST /v1/auth/social", s.socialLogin)
	s.mux.Handle("POST /v1/auth/logout", s.authRequired(s.logout, roleAny...))
	s.mux.HandleFunc("POST /v1/auth/otp/verify", s.verifyOTPLogin)
	s.mux.HandleFunc("GET /v1/auth/providers", s.authProviders)

	s.mux.HandleFunc("GET /v1/travelers/listings", s.listTravelerListings)
	// Requests are not public: clients must not see other clients' requests.
	// Travelers/admins can browse them for matching.
	s.mux.Handle("GET /v1/clients/requests", s.authRequired(s.listDeliveryRequests, roleAny...))
	s.mux.HandleFunc("GET /v1/tracking/", s.listTracking)

	s.mux.Handle("GET /v1/me", s.authRequired(s.me, roleAny...))
	s.mux.Handle("DELETE /v1/me", s.authRequired(s.deleteMe, roleAny...))
	s.mux.Handle("GET /v1/me/profile", s.authRequired(s.meProfile, roleAny...))
	s.mux.Handle("PUT /v1/me/profile", s.authRequired(s.updateMeProfile, roleAny...))
	s.mux.Handle("GET /v1/me/payout-account", s.authRequired(s.myPayoutAccount, roleAny...))
	s.mux.Handle("GET /v1/me/listings", s.authRequired(s.myListings, roleAny...))
	s.mux.Handle("GET /v1/me/requests", s.authRequired(s.myRequests, roleAny...))
	s.mux.Handle("GET /v1/me/matches", s.authRequired(s.myMatches, roleAny...))
	s.mux.Handle("GET /v1/me/escrows", s.authRequired(s.myEscrows, roleAny...))
	s.mux.Handle("GET /v1/me/kyc/verifications", s.authRequired(s.myKYCVerifications, roleAny...))
	s.mux.Handle("GET /v1/me/packages/verifications", s.authRequired(s.myPackageVerifications, roleAny...))
	s.mux.Handle("GET /v1/me/notifications", s.authRequired(s.myNotifications, roleAny...))
	s.mux.Handle("GET /v1/me/notifications/unread-count", s.authRequired(s.myNotificationsUnreadCount, roleAny...))
	s.mux.Handle("POST /v1/me/notifications/", s.authRequired(s.markNotificationRead, roleAny...))
	s.mux.Handle("DELETE /v1/me/notifications/", s.authRequired(s.deleteNotification, roleAny...))
	s.mux.Handle("POST /v1/uploads/presign", s.authRequired(s.createUploadToken, roleAny...))
	s.mux.HandleFunc("PUT /v1/uploads/", s.uploadViaSignedURL)

	s.mux.Handle("POST /v1/travelers/listings", s.authRequired(s.createTravelerListing, roleTravelerOrAdmin...))
	s.mux.Handle("POST /v1/clients/requests", s.authRequired(s.createDeliveryRequest, roleClientOrAdmin...))
	s.mux.Handle("POST /v1/matches", s.authRequired(s.createMatch, roleAny...))
	s.mux.Handle("POST /v1/escrows", s.authRequired(s.createEscrow, roleClientOrAdmin...))
	s.mux.Handle("POST /v1/escrows/", s.authRequired(s.escrowAction, roleClientOrAdmin...))
	s.mux.Handle("DELETE /v1/me/escrows/", s.authRequired(s.deleteEscrow, roleAny...))
	s.mux.Handle("POST /v1/kyc/verifications", s.authRequired(s.createKYCVerification, roleAny...))
	s.mux.Handle("POST /v1/packages/verifications", s.authRequired(s.createPackageVerification, roleClientOrAdmin...))
	s.mux.Handle("POST /v1/tracking/events", s.authRequired(s.addTrackingEvent, roleTravelerOrAdmin...))
	s.mux.Handle("POST /v1/payments/connect/onboard", s.authRequired(s.createPayoutOnboarding, roleTravelerOrAdmin...))

	s.mux.Handle("GET /v1/admin/users", s.authRequired(s.adminUsers, roleAdminOnly...))
	s.mux.Handle("GET /v1/admin/escrows", s.authRequired(s.adminEscrows, roleAdminOnly...))
	s.mux.Handle("GET /v1/admin/commissions/summary", s.authRequired(s.adminCommissionSummary, roleAdminOnly...))
	s.mux.Handle("GET /v1/admin/kyc/verifications", s.authRequired(s.adminKYCList, roleAdminOnly...))
	s.mux.Handle("POST /v1/admin/kyc/verifications/", s.authRequired(s.adminKYCReview, roleAdminOnly...))
	s.mux.Handle("GET /v1/admin/packages/verifications", s.authRequired(s.adminPackageList, roleAdminOnly...))
	s.mux.Handle("POST /v1/admin/packages/verifications/", s.authRequired(s.adminPackageReview, roleAdminOnly...))
	s.mux.Handle("GET /v1/admin/oauth/providers", s.authRequired(s.adminOAuthProviders, roleAdminOnly...))
	s.mux.Handle("PUT /v1/admin/oauth/providers/", s.authRequired(s.adminUpsertOAuthProvider, roleAdminOnly...))
	s.mux.HandleFunc("POST /v1/payments/webhooks/", s.paymentWebhook)
}

var (
	roleAny             = []string{string(domain.RoleClient), string(domain.RoleTraveler), string(domain.RoleAdmin)}
	roleTravelerOrAdmin = []string{string(domain.RoleTraveler), string(domain.RoleAdmin)}
	roleClientOrAdmin   = []string{string(domain.RoleClient), string(domain.RoleAdmin)}
	roleAdminOnly       = []string{string(domain.RoleAdmin)}
)

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		writeErr(w, http.StatusUnauthorized, "missing bearer token")
		return
	}
	token := strings.TrimPrefix(header, "Bearer ")
	claims, err := s.authManager.Parse(token)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "invalid token")
		return
	}
	if err := s.revokeToken(token, claims.ExpiresAt.Time); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to revoke token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (s *Server) revokeToken(token string, expiry time.Time) error {
	s.revokedTokensMu.Lock()
	defer s.revokedTokensMu.Unlock()
	if expiry.Before(time.Now().UTC()) {
		return nil
	}
	s.revokedTokens[token] = expiry
	return nil
}

func (s *Server) isTokenRevoked(token string) bool {
	s.revokedTokensMu.Lock()
	defer s.revokedTokensMu.Unlock()
	if expiry, ok := s.revokedTokens[token]; ok {
		if expiry.After(time.Now().UTC()) {
			return true
		}
		delete(s.revokedTokens, token)
	}
	return false
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email              string `json:"email"`
		Password           string `json:"password"`
		FullName           string `json:"full_name"`
		Role               string `json:"role"`
		AvatarURL          string `json:"avatar_url"`
		Phone              string `json:"phone"`
		Bio                string `json:"bio"`
		PermanentAddress   string `json:"permanent_address"`
		PassportNumber     string `json:"passport_number"`
		CountryOfResidence string `json:"country_of_residence"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if in.Email == "" || in.Password == "" || in.FullName == "" {
		writeErr(w, http.StatusBadRequest, "email, password and full_name are required")
		return
	}
	if err := validateStrongPassword(in.Password); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	role := domain.UserRole(in.Role)
	if role != domain.RoleClient && role != domain.RoleTraveler && role != domain.RoleAdmin {
		writeErr(w, http.StatusBadRequest, "role must be client, traveler or admin")
		return
	}
	in.Phone = strings.TrimSpace(in.Phone)
	in.PermanentAddress = strings.TrimSpace(in.PermanentAddress)
	in.PassportNumber = strings.TrimSpace(in.PassportNumber)
	in.CountryOfResidence = strings.TrimSpace(in.CountryOfResidence)
	if role == domain.RoleClient && in.Phone == "" {
		writeErr(w, http.StatusBadRequest, "phone is required for client registration")
		return
	}
	if in.Phone != "" && !isLikelyE164Phone(in.Phone) {
		writeErr(w, http.StatusBadRequest, "phone must be in international format, e.g. +14155550123")
		return
	}
	if role == domain.RoleTraveler {
		if in.Phone == "" || in.PermanentAddress == "" || in.PassportNumber == "" || in.CountryOfResidence == "" {
			writeErr(w, http.StatusBadRequest, "traveler requires phone, permanent_address, passport_number and country_of_residence")
			return
		}
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to hash password")
		return
	}
	user, err := s.repo.CreateUser(domain.User{
		Email:              in.Email,
		FullName:           in.FullName,
		Role:               role,
		PasswordHash:       string(hash),
		AvatarURL:          in.AvatarURL,
		Phone:              in.Phone,
		Bio:                in.Bio,
		PermanentAddress:   in.PermanentAddress,
		PassportNumber:     in.PassportNumber,
		CountryOfResidence: in.CountryOfResidence,
		KYCStatus:          "unverified",
	})
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if user.Role == domain.RoleClient {
		s.writeOTPChallenge(w, user, "register")
		return
	}
	token, err := s.authManager.Issue(user.ID, user.Role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to issue token")
		return
	}
	user.PasswordHash = ""
	writeJSON(w, http.StatusCreated, map[string]any{"user": user, "token": token})
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	emailKey := strings.ToLower(strings.TrimSpace(in.Email))
	if ok, retryAfter := s.allowedAuthAttempt(s.loginAttempts, "login:"+emailKey); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
		writeErr(w, http.StatusTooManyRequests, "too many failed login attempts; try again later")
		return
	}
	user, err := s.repo.GetUserByEmail(in.Email)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(in.Password)) != nil {
		s.recordAuthFailure(s.loginAttempts, "login:"+emailKey, s.authMaxFails, s.authLockWindow)
		writeErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	s.clearAuthFailures(s.loginAttempts, "login:"+emailKey)
	if user.Role == domain.RoleClient {
		s.writeOTPChallenge(w, user, "login")
		return
	}
	token, err := s.authManager.Issue(user.ID, user.Role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to issue token")
		return
	}
	user.PasswordHash = ""
	writeJSON(w, http.StatusOK, map[string]any{"user": user, "token": token})
}

func (s *Server) socialLogin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Provider    string `json:"provider"`
		AccessToken string `json:"access_token"`
		IDToken     string `json:"id_token"`
		Email       string `json:"email"`
		FullName    string `json:"full_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	provider := strings.ToLower(strings.TrimSpace(in.Provider))
	switch provider {
	case "google", "apple":
	default:
		writeErr(w, http.StatusBadRequest, "provider must be google or apple")
		return
	}

	configs, cfgErr := s.repo.ListOAuthProviderConfigs()
	if cfgErr != nil {
		writeErr(w, http.StatusInternalServerError, "failed to load auth provider configs")
		return
	}
	enabledByProvider := map[string]bool{}
	for _, cfg := range configs {
		enabledByProvider[cfg.Provider] = cfg.Enabled
	}
	if enabled, ok := enabledByProvider[provider]; ok && !enabled {
		writeErr(w, http.StatusForbidden, "provider is currently disabled")
		return
	}

	var (
		providerUserID string
		email          string
		fullName       string
		avatarURL      string
		err            error
	)
	switch provider {
	case "google":
		if strings.TrimSpace(in.AccessToken) == "" {
			writeErr(w, http.StatusBadRequest, "access_token is required")
			return
		}
		providerUserID, email, fullName, avatarURL, err = s.verifySocialAccessToken(provider, in.AccessToken)
	case "apple":
		if strings.TrimSpace(in.IDToken) == "" {
			writeErr(w, http.StatusBadRequest, "id_token is required")
			return
		}
		providerUserID, email, fullName, err = s.verifyAppleIDToken(in.IDToken, in.Email, in.FullName)
	default:
		err = errors.New("unsupported provider")
	}
	if err != nil {
		writeErr(w, http.StatusUnauthorized, err.Error())
		return
	}

	user, err := s.repo.SocialLogin(provider, providerUserID, email, fullName, avatarURL)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	token, err := s.authManager.Issue(user.ID, user.Role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to issue token")
		return
	}
	user.PasswordHash = ""
	writeJSON(w, http.StatusOK, map[string]any{"user": user, "token": token})
}

func (s *Server) authProviders(w http.ResponseWriter, _ *http.Request) {
	out, err := s.repo.ListOAuthProviderConfigs()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) verifyOTPLogin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		SessionID string `json:"otp_session_id"`
		Code      string `json:"otp_code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if strings.TrimSpace(in.SessionID) == "" || strings.TrimSpace(in.Code) == "" {
		writeErr(w, http.StatusBadRequest, "otp_session_id and otp_code are required")
		return
	}
	sessionKey := "otp:" + strings.TrimSpace(in.SessionID)
	if ok, retryAfter := s.allowedAuthAttempt(s.otpAttempts, sessionKey); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
		writeErr(w, http.StatusTooManyRequests, "too many failed otp attempts; try again later")
		return
	}
	user, err := s.repo.VerifyOTPChallenge(in.SessionID, in.Code)
	if err != nil {
		s.recordAuthFailure(s.otpAttempts, sessionKey, s.otpMaxFails, s.otpLockWindow)
		writeErr(w, http.StatusUnauthorized, err.Error())
		return
	}
	s.clearAuthFailures(s.otpAttempts, sessionKey)
	token, err := s.authManager.Issue(user.ID, user.Role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to issue token")
		return
	}
	user.PasswordHash = ""
	writeJSON(w, http.StatusOK, map[string]any{"user": user, "token": token})
}

func (s *Server) writeOTPChallenge(w http.ResponseWriter, user domain.User, purpose string) {
	if strings.TrimSpace(user.Phone) == "" {
		writeErr(w, http.StatusBadRequest, "phone is required for otp verification")
		return
	}
	code, err := generateOTPCode(6)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to generate otp code")
		return
	}
	sessionID, err := s.repo.CreateOTPChallenge(user.ID, user.Phone, purpose, code, time.Now().UTC().Add(s.otpTTL))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to create otp challenge")
		return
	}
	if !s.otpDevMode {
		if err := s.sendSMSOTP(user.Phone, code, purpose); err != nil {
			writeErr(w, http.StatusInternalServerError, err.Error())
			return
		}
	}
	user.PasswordHash = ""
	resp := map[string]any{
		"otp_required":   true,
		"otp_session_id": sessionID,
		"user":           user,
		"purpose":        purpose,
		"expires_in_sec": int(s.otpTTL.Seconds()),
	}
	if s.otpDevMode {
		resp["dev_otp_code"] = code
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) sendSMSOTP(toPhone, code, purpose string) error {
	toPhone = strings.TrimSpace(toPhone)
	if !isLikelyE164Phone(toPhone) {
		return errors.New("invalid phone format for sms delivery")
	}
	if s.twilioSID == "" || s.twilioToken == "" || s.twilioFrom == "" {
		return errors.New("sms provider not configured on server")
	}
	body := fmt.Sprintf("Your Elysian Flee OTP for %s is %s. It expires in %d minutes.",
		strings.TrimSpace(purpose), code, int(s.otpTTL.Minutes()))
	form := url.Values{}
	form.Set("To", toPhone)
	form.Set("From", s.twilioFrom)
	form.Set("Body", body)
	endpoint := fmt.Sprintf("https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json", s.twilioSID)
	req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return errors.New("failed to prepare sms request")
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(s.twilioSID, s.twilioToken)
	client := &http.Client{Timeout: 12 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return errors.New("failed to send sms otp")
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		return fmt.Errorf("sms provider error (%d): %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	return nil
}

func (s *Server) verifySocialAccessToken(provider, accessToken string) (providerUserID, email, fullName, avatarURL string, err error) {
	url := ""
	switch provider {
	case "google":
		url = "https://openidconnect.googleapis.com/v1/userinfo"
	case "apple":
		return "", "", "", "", errors.New("apple sign-in is not yet enabled in backend")
	default:
		return "", "", "", "", errors.New("unsupported provider")
	}

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", "", "", "", err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", "", "", errors.New("failed to verify social token")
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 400 {
		return "", "", "", "", fmt.Errorf("provider token verification failed (%d)", resp.StatusCode)
	}

	var claims struct {
		Sub           string `json:"sub"`
		Email         string `json:"email"`
		Name          string `json:"name"`
		Picture       string `json:"picture"`
		PreferredName string `json:"preferred_username"`
	}
	if err := json.Unmarshal(body, &claims); err != nil {
		return "", "", "", "", errors.New("failed to decode provider profile")
	}
	if strings.TrimSpace(claims.Email) == "" {
		claims.Email = strings.TrimSpace(claims.PreferredName)
	}
	if strings.TrimSpace(claims.Sub) == "" || strings.TrimSpace(claims.Email) == "" {
		return "", "", "", "", errors.New("provider response missing required identity claims")
	}
	return strings.TrimSpace(claims.Sub), strings.TrimSpace(strings.ToLower(claims.Email)), strings.TrimSpace(claims.Name), strings.TrimSpace(claims.Picture), nil
}

func (s *Server) verifyAppleIDToken(idToken, fallbackEmail, fallbackName string) (providerUserID, email, fullName string, err error) {
	parser := jwt.NewParser()
	unverified := jwt.MapClaims{}
	token, _, err := parser.ParseUnverified(idToken, unverified)
	if err != nil {
		return "", "", "", errors.New("invalid apple token")
	}
	kid, _ := token.Header["kid"].(string)
	if strings.TrimSpace(kid) == "" {
		return "", "", "", errors.New("apple token missing key id")
	}

	pubKey, err := s.fetchApplePublicKey(kid)
	if err != nil {
		return "", "", "", err
	}

	claims := jwt.MapClaims{}
	_, err = jwt.ParseWithClaims(idToken, claims, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != jwt.SigningMethodRS256.Alg() {
			return nil, errors.New("unexpected signing algorithm")
		}
		return pubKey, nil
	}, jwt.WithIssuer("https://appleid.apple.com"), jwt.WithLeeway(30*time.Second))
	if err != nil {
		return "", "", "", errors.New("apple token verification failed")
	}

	sub, _ := claims["sub"].(string)
	mail, _ := claims["email"].(string)
	name, _ := claims["name"].(string)
	if strings.TrimSpace(mail) == "" {
		mail = strings.TrimSpace(fallbackEmail)
	}
	if strings.TrimSpace(name) == "" {
		name = strings.TrimSpace(fallbackName)
	}
	if strings.TrimSpace(sub) == "" || strings.TrimSpace(mail) == "" {
		return "", "", "", errors.New("apple token missing identity claims")
	}
	return strings.TrimSpace(sub), strings.TrimSpace(strings.ToLower(mail)), strings.TrimSpace(name), nil
}

func (s *Server) fetchApplePublicKey(kid string) (*rsa.PublicKey, error) {
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return nil, errors.New("failed to download apple keys")
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, errors.New("apple keys endpoint unavailable")
	}
	var jwks struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&jwks); err != nil {
		return nil, errors.New("failed to decode apple keys")
	}
	for _, key := range jwks.Keys {
		if key.Kid != kid || key.Kty != "RSA" {
			continue
		}
		n, err := base64.RawURLEncoding.DecodeString(key.N)
		if err != nil {
			return nil, errors.New("invalid apple key modulus")
		}
		eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
		if err != nil {
			return nil, errors.New("invalid apple key exponent")
		}
		e := 0
		for _, b := range eBytes {
			e = e*256 + int(b)
		}
		if e == 0 {
			return nil, errors.New("invalid apple key exponent value")
		}
		return &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: e}, nil
	}
	return nil, errors.New("matching apple key not found")
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	user, err := s.repo.GetUserByID(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	user.PasswordHash = ""
	writeJSON(w, http.StatusOK, user)
}

func (s *Server) deleteMe(w http.ResponseWriter, r *http.Request) {
	if err := s.repo.DeleteUserByID(userIDFromContext(r)); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "deleted"})
}

func (s *Server) meProfile(w http.ResponseWriter, r *http.Request) {
	s.me(w, r)
}

func (s *Server) updateMeProfile(w http.ResponseWriter, r *http.Request) {
	user, err := s.repo.GetUserByID(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	var in struct {
		FullName           string `json:"full_name"`
		AvatarURL          string `json:"avatar_url"`
		Phone              string `json:"phone"`
		Bio                string `json:"bio"`
		PermanentAddress   string `json:"permanent_address"`
		CountryOfResidence string `json:"country_of_residence"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if strings.TrimSpace(in.FullName) == "" {
		writeErr(w, http.StatusBadRequest, "full_name is required")
		return
	}
	user.FullName = in.FullName
	user.AvatarURL = in.AvatarURL
	user.Phone = in.Phone
	user.Bio = in.Bio
	user.PermanentAddress = in.PermanentAddress
	user.CountryOfResidence = in.CountryOfResidence
	updated, err := s.repo.UpdateUserProfile(user)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	updated.PasswordHash = ""
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) createTravelerListing(w http.ResponseWriter, r *http.Request) {
	var in domain.TravelerListing
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	in.TravelerID = userIDFromContext(r)
	if err := validateTravelerListing(in); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	out, err := s.repo.CreateTravelerListing(in)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	out = s.enrichTravelerListing(out)
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) listTravelerListings(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListTravelerListings(r.URL.Query().Get("destination"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out = s.enrichTravelerListings(out)
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) myListings(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListTravelerListingsByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out = s.enrichTravelerListings(out)
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createDeliveryRequest(w http.ResponseWriter, r *http.Request) {
	var in domain.DeliveryRequest
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	in.ClientID = userIDFromContext(r)
	if err := validateDeliveryRequest(in); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	// Enforce "unique per client" for open requests with identical details.
	// This prevents accidental duplicate submissions from the same client.
	existing, err := s.repo.ListDeliveryRequestsByUser(in.ClientID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	for _, e := range existing {
		if e.Status != "open" {
			continue
		}
		if e.Origin == in.Origin &&
			e.Destination == in.Destination &&
			e.DestinationType == in.DestinationType &&
			e.RecipientName == in.RecipientName &&
			e.RecipientPhone == in.RecipientPhone &&
			e.DropoffAddress == in.DropoffAddress &&
			e.DropoffInstructions == in.DropoffInstructions &&
			e.WeightKg == in.WeightKg &&
			e.DeclaredValue == in.DeclaredValue &&
			e.PackageDescription == in.PackageDescription {
			writeErr(w, http.StatusBadRequest, "duplicate request: you already have an identical open request")
			return
		}
	}
	out, err := s.repo.CreateDeliveryRequest(in)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	out = s.enrichDeliveryRequest(out)
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) listDeliveryRequests(w http.ResponseWriter, r *http.Request) {
	destination := r.URL.Query().Get("destination")
	role := roleFromContext(r)
	userID := userIDFromContext(r)
	if role == string(domain.RoleClient) {
		// Clients can only see their own requests.
		out, err := s.repo.ListDeliveryRequestsByUser(userID)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err.Error())
			return
		}
		if destination != "" {
			filtered := []domain.DeliveryRequest{}
			for _, req := range out {
				if strings.EqualFold(req.Destination, destination) {
					filtered = append(filtered, req)
				}
			}
			out = filtered
		}
		out = s.enrichDeliveryRequests(out)
		writeJSON(w, http.StatusOK, out)
		return
	}
	// Travelers/admins can browse requests to match against listings.
	out, err := s.repo.ListDeliveryRequests(destination)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out = s.enrichDeliveryRequests(out)
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) myRequests(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListDeliveryRequestsByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out = s.enrichDeliveryRequests(out)
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createMatch(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ListingID           string     `json:"listing_id"`
		RequestID           string     `json:"request_id"`
		AgreedPrice         float64    `json:"agreed_price"`
		EstimatedDeliveryAt *time.Time `json:"estimated_delivery_at"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if in.ListingID == "" || in.RequestID == "" || in.AgreedPrice <= 0 {
		writeErr(w, http.StatusBadRequest, "listing_id, request_id and positive agreed_price are required")
		return
	}
	out, err := s.repo.CreateMatch(domain.Match{
		ListingID:           in.ListingID,
		RequestID:           in.RequestID,
		AgreedPrice:         in.AgreedPrice,
		EstimatedDeliveryAt: in.EstimatedDeliveryAt,
	})
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) myMatches(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListMatchesByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createEscrow(w http.ResponseWriter, r *http.Request) {
	var in struct {
		MatchID  string  `json:"match_id"`
		Amount   float64 `json:"amount"`
		Currency string  `json:"currency"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if in.MatchID == "" || in.Amount <= 0 {
		writeErr(w, http.StatusBadRequest, "match_id and positive amount are required")
		return
	}
	if in.Currency == "" {
		in.Currency = "USD"
	}
	out, err := s.repo.CreateEscrow(in.MatchID, strings.ToUpper(in.Currency), in.Amount, s.commissionRate)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) escrowAction(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseActionPath(r.URL.Path, "/v1/escrows/")
	if !ok {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	var (
		out domain.Escrow
		err error
	)
	switch action {
	case "fund":
		key := escrowActionIdempotencyKey(r, id, action)
		out, err = s.repo.GetEscrowByID(id)
		if err != nil {
			break
		}
		if out.Status == "funded" || out.Status == "released" {
			writeJSON(w, http.StatusOK, out)
			return
		}
		result, pErr := s.paymentProvider.CreateEscrowHold(payments.EscrowHoldRequest{
			EscrowID:       id,
			ClientUserID:   userIDFromContext(r),
			Currency:       out.Currency,
			Amount:         out.Amount,
			IdempotencyKey: key,
		})
		if pErr != nil {
			writeErr(w, http.StatusBadGateway, "payment hold failed: "+pErr.Error())
			return
		}
		out, err = s.repo.FundEscrow(id)
		if err != nil {
			break
		}
		if updated, uErr := s.repo.SetEscrowPayout(id, result.Provider, result.Reference, "hold_"+result.Status); uErr == nil {
			out = updated
		}
	case "release":
		existing, gErr := s.repo.GetEscrowByID(id)
		if gErr != nil {
			err = gErr
			break
		}
		match, mErr := s.repo.GetMatchByID(existing.MatchID)
		if mErr != nil {
			err = mErr
			break
		}
		listing, lErr := s.repo.GetTravelerListingByID(match.ListingID)
		if lErr != nil {
			err = lErr
			break
		}
		traveler, tErr := s.repo.GetUserByID(listing.TravelerID)
		if tErr != nil {
			err = tErr
			break
		}
		if strings.TrimSpace(traveler.PayoutAccountID) == "" {
			writeErr(w, http.StatusBadRequest, "traveler payout account is not onboarded")
			return
		}
		out, err = s.repo.ReleaseEscrow(id)
		if err == nil {
			key := escrowActionIdempotencyKey(r, id, action)
			result, pErr := s.paymentProvider.ReleasePayout(payments.EscrowPayoutRequest{
				EscrowID:          id,
				TravelerUserID:    traveler.ID,
				TravelerAccountID: traveler.PayoutAccountID,
				HoldReference:     existing.PayoutReference,
				Currency:          out.Currency,
				Amount:            out.TravelerAmount,
				IdempotencyKey:    key,
			})
			if pErr == nil {
				if updated, uErr := s.repo.SetEscrowPayout(id, result.Provider, result.Reference, result.Status); uErr == nil {
					out = updated
				}
			} else {
				if updated, uErr := s.repo.SetEscrowPayout(id, s.paymentProvider.Name(), existing.PayoutReference, "payout_failed"); uErr == nil {
					out = updated
				}
			}
		}
	case "refund":
		existing, gErr := s.repo.GetEscrowByID(id)
		if gErr != nil {
			err = gErr
			break
		}
		out, err = s.repo.RefundEscrow(id)
		if err == nil {
			key := escrowActionIdempotencyKey(r, id, action)
			result, pErr := s.paymentProvider.RefundEscrow(payments.EscrowRefundRequest{
				EscrowID:       id,
				ClientUserID:   userIDFromContext(r),
				HoldReference:  existing.PayoutReference,
				Currency:       out.Currency,
				Amount:         out.Amount,
				IdempotencyKey: key,
			})
			if pErr == nil {
				if updated, uErr := s.repo.SetEscrowPayout(id, result.Provider, result.Reference, result.Status); uErr == nil {
					out = updated
				}
			}
		}
	case "dispute":
		out, err = s.repo.DisputeEscrow(id)
		if err == nil {
			if updated, uErr := s.repo.SetEscrowPayout(id, s.paymentProvider.Name(), "", "disputed"); uErr == nil {
				out = updated
			}
		}
	default:
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) deleteEscrow(w http.ResponseWriter, r *http.Request) {
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/me/escrows/"), "/")
	if id == "" {
		writeErr(w, http.StatusBadRequest, "escrow id is required")
		return
	}
	if err := s.repo.DeleteEscrowByUser(id, userIDFromContext(r)); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) myEscrows(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListEscrowsByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createKYCVerification(w http.ResponseWriter, r *http.Request) {
	var in domain.KYCVerification
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	in.UserID = userIDFromContext(r)
	if in.DocumentType == "" || in.DocumentReference == "" || in.AddressProofRef == "" {
		writeErr(w, http.StatusBadRequest, "document_type, document_reference and address_proof_ref are required")
		return
	}
	out, err := s.repo.CreateKYCVerification(in)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) myKYCVerifications(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListKYCVerifications(r.URL.Query().Get("status"), userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createPackageVerification(w http.ResponseWriter, r *http.Request) {
	var in domain.PackageVerification
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if in.RequestID == "" || in.DeclaredContents == "" || in.ReceiptRef == "" {
		writeErr(w, http.StatusBadRequest, "request_id, declared_contents and receipt_ref are required")
		return
	}
	out, err := s.repo.CreatePackageVerification(in)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) myPackageVerifications(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromContext(r)
	requests, err := s.repo.ListDeliveryRequestsByUser(userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	requestSet := map[string]struct{}{}
	for _, req := range requests {
		requestSet[req.ID] = struct{}{}
	}
	all, err := s.repo.ListPackageVerifications(r.URL.Query().Get("status"), "")
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out := []domain.PackageVerification{}
	for _, p := range all {
		if _, ok := requestSet[p.RequestID]; ok {
			out = append(out, p)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createUploadToken(w http.ResponseWriter, r *http.Request) {
	var in struct {
		FileName    string `json:"file_name"`
		ContentType string `json:"content_type"`
		Kind        string `json:"kind"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	fileName := sanitizeFileName(in.FileName)
	if fileName == "" {
		writeErr(w, http.StatusBadRequest, "file_name is required")
		return
	}
	contentType := strings.TrimSpace(in.ContentType)
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	kind := strings.TrimSpace(in.Kind)
	if kind == "" {
		kind = "generic"
	}
	payload := uploadTokenPayload{
		UserID:      userIDFromContext(r),
		FileName:    fileName,
		ContentType: contentType,
		Kind:        kind,
		ExpiresAt:   time.Now().UTC().Add(s.uploadTokenTTL).Unix(),
	}
	token, err := s.signUploadToken(payload)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to create upload token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"method":      "PUT",
		"upload_url":  "/v1/uploads/" + token,
		"expires_in":  int(s.uploadTokenTTL.Seconds()),
		"contentType": contentType,
		"kind":        kind,
	})
}

func (s *Server) uploadViaSignedURL(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		writeErr(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	token := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/uploads/"), "/")
	if token == "" {
		writeErr(w, http.StatusBadRequest, "upload token is required")
		return
	}
	payload, err := s.verifyUploadToken(token)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, err.Error())
		return
	}
	if time.Now().UTC().Unix() > payload.ExpiresAt {
		writeErr(w, http.StatusUnauthorized, "upload token expired")
		return
	}
	if err := os.MkdirAll(filepath.Join(s.uploadDir, payload.UserID), 0o755); err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to initialize upload storage")
		return
	}
	fileName := sanitizeFileName(payload.FileName)
	path := filepath.Join(s.uploadDir, payload.UserID, fmt.Sprintf("%d_%s", time.Now().UTC().Unix(), fileName))
	file, err := os.Create(path)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to create upload file")
		return
	}
	defer file.Close()
	const maxUploadBytes = 10 << 20
	written, err := io.Copy(file, io.LimitReader(r.Body, maxUploadBytes))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "failed to write uploaded file")
		return
	}
	fileRef := strings.ReplaceAll(filepath.ToSlash(path), "\\", "/")
	writeJSON(w, http.StatusOK, map[string]any{
		"file_ref":      fileRef,
		"bytes_written": written,
		"kind":          payload.Kind,
	})
}

func (s *Server) myNotifications(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListNotificationsByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) myNotificationsUnreadCount(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListNotificationsByUser(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	count := 0
	for _, n := range out {
		if n.ReadAt == nil {
			count++
		}
	}
	writeJSON(w, http.StatusOK, map[string]int{"unread_count": count})
}

func (s *Server) markNotificationRead(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseActionPath(r.URL.Path, "/v1/me/notifications/")
	if !ok || action != "read" {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	out, err := s.repo.MarkNotificationRead(id, userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) deleteNotification(w http.ResponseWriter, r *http.Request) {
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/me/notifications/"), "/")
	if id == "" {
		writeErr(w, http.StatusBadRequest, "notification id is required")
		return
	}
	if err := s.repo.DeleteNotification(id, userIDFromContext(r)); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) paymentWebhook(w http.ResponseWriter, r *http.Request) {
	provider := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/payments/webhooks/"), "/")
	if provider == "" {
		writeErr(w, http.StatusBadRequest, "provider is required in path")
		return
	}
	if provider != s.paymentProvider.Name() {
		writeErr(w, http.StatusNotFound, "unsupported payment provider")
		return
	}
	payload, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid payload")
		return
	}
	sig := strings.TrimSpace(r.Header.Get("X-Signature"))
	if strings.EqualFold(provider, "stripe_connect") {
		sig = strings.TrimSpace(r.Header.Get("Stripe-Signature"))
	}
	event, err := s.paymentProvider.ParseWebhook(payload, sig)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if event.Provider == "" {
		event.Provider = provider
	}
	_, existingErr := s.repo.GetPaymentEventByProviderEventID(event.Provider, event.ProviderEventID)
	if existingErr == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "duplicate": true})
		return
	}
	if !strings.Contains(strings.ToLower(existingErr.Error()), "not found") {
		writeErr(w, http.StatusInternalServerError, existingErr.Error())
		return
	}
	_, createErr := s.repo.CreatePaymentEvent(domain.PaymentEvent{
		Provider:        event.Provider,
		ProviderEventID: event.ProviderEventID,
		EventType:       event.EventType,
		Payload:         event.Payload,
	})
	if createErr != nil {
		if strings.Contains(strings.ToLower(createErr.Error()), "duplicate") {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "duplicate": true})
			return
		}
		writeErr(w, http.StatusBadRequest, createErr.Error())
		return
	}
	if strings.TrimSpace(event.EscrowID) != "" && strings.TrimSpace(event.Status) != "" {
		_, _ = s.repo.SetEscrowPayout(event.EscrowID, event.Provider, event.Reference, event.Status)
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) myPayoutAccount(w http.ResponseWriter, r *http.Request) {
	user, err := s.repo.GetUserByID(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"provider":   user.PayoutProvider,
		"account_id": user.PayoutAccountID,
		"status":     user.PayoutAccountStatus,
	})
}

func (s *Server) createPayoutOnboarding(w http.ResponseWriter, r *http.Request) {
	user, err := s.repo.GetUserByID(userIDFromContext(r))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if user.Role != domain.RoleTraveler && user.Role != domain.RoleAdmin {
		writeErr(w, http.StatusForbidden, "only traveler/admin can onboard payout account")
		return
	}
	var in struct {
		Country    string `json:"country"`
		Business   string `json:"business_type"`
		RefreshURL string `json:"refresh_url"`
		ReturnURL  string `json:"return_url"`
	}
	_ = json.NewDecoder(r.Body).Decode(&in)

	var accountID string
	status := strings.TrimSpace(user.PayoutAccountStatus)
	if strings.TrimSpace(user.PayoutAccountID) == "" {
		acct, pErr := s.paymentProvider.EnsurePayoutAccount(payments.PayoutAccountRequest{
			UserID:   user.ID,
			Email:    user.Email,
			Country:  in.Country,
			Business: in.Business,
		})
		if pErr != nil {
			writeErr(w, http.StatusBadGateway, "payout account creation failed: "+pErr.Error())
			return
		}
		accountID = strings.TrimSpace(acct.AccountID)
		status = strings.TrimSpace(acct.Status)
		if _, uErr := s.repo.SetUserPayoutAccount(user.ID, acct.Provider, accountID, status); uErr != nil {
			writeErr(w, http.StatusInternalServerError, uErr.Error())
			return
		}
	} else {
		accountID = strings.TrimSpace(user.PayoutAccountID)
	}
	link, lErr := s.paymentProvider.CreatePayoutOnboardingLink(payments.PayoutOnboardingLinkRequest{
		AccountID:  accountID,
		RefreshURL: in.RefreshURL,
		ReturnURL:  in.ReturnURL,
	})
	if lErr != nil {
		writeErr(w, http.StatusBadGateway, "payout onboarding link failed: "+lErr.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"provider":       s.paymentProvider.Name(),
		"account_id":     accountID,
		"account_status": status,
		"onboarding_url": link.URL,
	})
}

func (s *Server) addTrackingEvent(w http.ResponseWriter, r *http.Request) {
	var in struct {
		MatchID    string `json:"match_id"`
		Status     string `json:"status"`
		Location   string `json:"location"`
		Notes      string `json:"notes"`
		OccurredAt string `json:"occurred_at"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	in.MatchID = strings.TrimSpace(in.MatchID)
	in.Status = strings.TrimSpace(in.Status)
	in.Location = strings.TrimSpace(in.Location)
	if in.MatchID == "" || in.Status == "" || in.Location == "" {
		writeErr(w, http.StatusBadRequest, "match_id, status and location are required")
		return
	}
	var occurredAt *time.Time
	if strings.TrimSpace(in.OccurredAt) != "" {
		t, err := parseFlexibleTimestamp(in.OccurredAt)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "occurred_at must be an ISO timestamp")
			return
		}
		occurredAt = &t
	}
	out, err := s.repo.AddTrackingEvent(domain.TrackingEvent{
		MatchID:    in.MatchID,
		Status:     in.Status,
		Location:   in.Location,
		Notes:      in.Notes,
		OccurredAt: occurredAt,
	})
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) listTracking(w http.ResponseWriter, r *http.Request) {
	matchID := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/tracking/"), "/")
	if matchID == "" {
		writeErr(w, http.StatusBadRequest, "match_id is required in path")
		return
	}
	out, err := s.repo.ListTrackingEvents(matchID)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminUsers(w http.ResponseWriter, _ *http.Request) {
	out, err := s.repo.ListUsers()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	for i := range out {
		out[i].PasswordHash = ""
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminEscrows(w http.ResponseWriter, _ *http.Request) {
	out, err := s.repo.ListEscrows()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminCommissionSummary(w http.ResponseWriter, _ *http.Request) {
	out, err := s.repo.GetCommissionSummary()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminKYCList(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListKYCVerifications(r.URL.Query().Get("status"), r.URL.Query().Get("user_id"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminKYCReview(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseActionPath(r.URL.Path, "/v1/admin/kyc/verifications/")
	if !ok || action != "review" {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	var in struct {
		Status string `json:"status"`
		Notes  string `json:"notes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	out, err := s.repo.ReviewKYCVerification(id, in.Status, in.Notes)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	msg := fmt.Sprintf("Your KYC review is now '%s'.", out.Status)
	notes := strings.TrimSpace(in.Notes)
	if notes != "" {
		msg += " " + notes
	}
	_, _ = s.repo.CreateNotification(domain.Notification{
		UserID:  out.UserID,
		Title:   "KYC Review Update",
		Message: msg,
		Type:    "kyc_review",
	})
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminPackageList(w http.ResponseWriter, r *http.Request) {
	out, err := s.repo.ListPackageVerifications(r.URL.Query().Get("status"), r.URL.Query().Get("request_id"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminPackageReview(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseActionPath(r.URL.Path, "/v1/admin/packages/verifications/")
	if !ok || action != "review" {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	var in struct {
		Status string `json:"status"`
		Notes  string `json:"notes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	out, err := s.repo.ReviewPackageVerification(id, in.Status, in.Notes)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	request, err := s.repo.GetDeliveryRequestByID(out.RequestID)
	if err == nil {
		msg := fmt.Sprintf("Your package verification for request '%s' is now '%s'.", out.RequestID, out.Status)
		notes := strings.TrimSpace(in.Notes)
		if notes != "" {
			msg += " " + notes
		}
		_, _ = s.repo.CreateNotification(domain.Notification{
			UserID:  request.ClientID,
			Title:   "Package Review Update",
			Message: msg,
			Type:    "package_review",
		})
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminOAuthProviders(w http.ResponseWriter, _ *http.Request) {
	out, err := s.repo.ListOAuthProviderConfigs()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) adminUpsertOAuthProvider(w http.ResponseWriter, r *http.Request) {
	provider := strings.Trim(strings.TrimPrefix(r.URL.Path, "/v1/admin/oauth/providers/"), "/")
	if provider == "" {
		writeErr(w, http.StatusBadRequest, "provider is required in path")
		return
	}
	var in struct {
		Enabled     bool   `json:"enabled"`
		ClientID    string `json:"client_id"`
		IOSClientID string `json:"ios_client_id"`
		WebClientID string `json:"web_client_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	out, err := s.repo.UpsertOAuthProviderConfig(domain.OAuthProviderConfig{
		Provider:    provider,
		Enabled:     in.Enabled,
		ClientID:    in.ClientID,
		IOSClientID: in.IOSClientID,
		WebClientID: in.WebClientID,
	})
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func parseActionPath(fullPath, prefix string) (id string, action string, ok bool) {
	path := strings.TrimPrefix(fullPath, prefix)
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

func escrowActionIdempotencyKey(r *http.Request, escrowID, action string) string {
	header := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if header != "" {
		return header
	}
	userID := userIDFromContext(r)
	return fmt.Sprintf("escrow:%s:%s:%s", strings.TrimSpace(escrowID), strings.TrimSpace(action), strings.TrimSpace(userID))
}

type uploadTokenPayload struct {
	UserID      string `json:"uid"`
	FileName    string `json:"name"`
	ContentType string `json:"ct"`
	Kind        string `json:"kind"`
	ExpiresAt   int64  `json:"exp"`
}

func (s *Server) signUploadToken(payload uploadTokenPayload) (string, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	bodyB64 := base64.RawURLEncoding.EncodeToString(body)
	mac := hmac.New(sha256.New, []byte(s.uploadSecret))
	mac.Write([]byte(bodyB64))
	sig := hex.EncodeToString(mac.Sum(nil))
	return bodyB64 + "." + sig, nil
}

func (s *Server) verifyUploadToken(token string) (uploadTokenPayload, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return uploadTokenPayload{}, errors.New("invalid upload token")
	}
	bodyB64 := parts[0]
	providedSig := parts[1]
	mac := hmac.New(sha256.New, []byte(s.uploadSecret))
	mac.Write([]byte(bodyB64))
	expectedSig := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(providedSig), []byte(expectedSig)) {
		return uploadTokenPayload{}, errors.New("invalid upload signature")
	}
	body, err := base64.RawURLEncoding.DecodeString(bodyB64)
	if err != nil {
		return uploadTokenPayload{}, errors.New("invalid upload token payload")
	}
	var payload uploadTokenPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		return uploadTokenPayload{}, errors.New("invalid upload token payload")
	}
	if strings.TrimSpace(payload.UserID) == "" || strings.TrimSpace(payload.FileName) == "" {
		return uploadTokenPayload{}, errors.New("invalid upload token")
	}
	return payload, nil
}

func sanitizeFileName(in string) string {
	in = strings.TrimSpace(in)
	in = strings.ReplaceAll(in, "\\", "_")
	in = strings.ReplaceAll(in, "/", "_")
	in = strings.ReplaceAll(in, "..", "_")
	if in == "" {
		return ""
	}
	return in
}

func (s *Server) allowedAuthAttempt(b map[string]authAttempt, key string) (bool, time.Duration) {
	s.attemptsMu.Lock()
	defer s.attemptsMu.Unlock()
	entry, ok := b[key]
	if !ok {
		return true, 0
	}
	now := time.Now().UTC()
	if entry.LockedUntil.After(now) {
		return false, entry.LockedUntil.Sub(now)
	}
	if !entry.LockedUntil.IsZero() {
		delete(b, key)
	}
	return true, 0
}

func (s *Server) recordAuthFailure(b map[string]authAttempt, key string, maxFails int, lockWindow time.Duration) {
	s.attemptsMu.Lock()
	defer s.attemptsMu.Unlock()
	entry := b[key]
	entry.Failures++
	if entry.Failures >= maxFails {
		entry.LockedUntil = time.Now().UTC().Add(lockWindow)
		entry.Failures = 0
	}
	b[key] = entry
}

func (s *Server) clearAuthFailures(b map[string]authAttempt, key string) {
	s.attemptsMu.Lock()
	defer s.attemptsMu.Unlock()
	delete(b, key)
}

func (s *Server) authRequired(next http.HandlerFunc, roles ...string) http.Handler {
	allowed := map[string]struct{}{}
	for _, r := range roles {
		allowed[r] = struct{}{}
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeErr(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		token := strings.TrimPrefix(header, "Bearer ")
		if s.isTokenRevoked(token) {
			writeErr(w, http.StatusUnauthorized, "token revoked")
			return
		}
		claims, err := s.authManager.Parse(token)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid token")
			return
		}
		if _, ok := allowed[claims.Role]; !ok {
			writeErr(w, http.StatusForbidden, "insufficient role")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUserIDKey, claims.Subject)
		ctx = context.WithValue(ctx, ctxRoleKey, claims.Role)
		next(w, r.WithContext(ctx))
	})
}

func validateTravelerListing(in domain.TravelerListing) error {
	if in.TravelerID == "" || in.Origin == "" || in.Destination == "" {
		return errors.New("traveler_id, origin and destination are required")
	}
	if in.MaxWeightKg <= 0 || in.PricePerKg <= 0 {
		return errors.New("max_weight_kg and price_per_kg must be positive")
	}
	if in.DepartureDate.IsZero() || in.ArrivalDate.IsZero() {
		return errors.New("departure_date and arrival_date are required")
	}
	if in.ArrivalDate.Before(in.DepartureDate) {
		return errors.New("arrival_date cannot be before departure_date")
	}
	if in.DestinationType != domain.DestinationCity && in.DestinationType != domain.DestinationCountry {
		return errors.New("destination_type must be city or country")
	}
	return nil
}

func validateDeliveryRequest(in domain.DeliveryRequest) error {
	if in.ClientID == "" || in.Origin == "" || in.Destination == "" {
		return errors.New("client_id, origin and destination are required")
	}
	if strings.TrimSpace(in.RecipientName) == "" {
		return errors.New("recipient_name is required")
	}
	if strings.TrimSpace(in.RecipientPhone) == "" {
		return errors.New("recipient_phone is required and must include country code, e.g. +14155550123")
	}
	if !isLikelyE164Phone(in.RecipientPhone) {
		return errors.New("recipient_phone must be in international format with country code, e.g. +14155550123")
	}
	if strings.TrimSpace(in.DropoffAddress) == "" {
		return errors.New("dropoff_address is required")
	}
	if in.WeightKg <= 0 || in.DeclaredValue < 0 {
		return errors.New("weight_kg must be positive and declared_value cannot be negative")
	}
	if in.DestinationType != domain.DestinationCity && in.DestinationType != domain.DestinationCountry {
		return errors.New("destination_type must be city or country")
	}
	return nil
}

func validateStrongPassword(password string) error {
	if len(password) < 10 {
		return errors.New("password must be at least 10 characters")
	}
	var hasUpper, hasLower, hasDigit, hasSymbol bool
	for _, r := range password {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		case unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasSymbol = true
		}
	}
	if !hasUpper || !hasLower || !hasDigit || !hasSymbol {
		return errors.New("password must include uppercase, lowercase, number and symbol")
	}
	return nil
}

func generateOTPCode(length int) (string, error) {
	if length <= 0 {
		length = 6
	}
	const digits = "0123456789"
	out := make([]byte, length)
	for i := 0; i < length; i++ {
		n, err := cryptorand.Int(cryptorand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return "", err
		}
		out[i] = digits[n.Int64()]
	}
	return string(out), nil
}

func isLikelyE164Phone(phone string) bool {
	phone = strings.TrimSpace(phone)
	if len(phone) < 8 || len(phone) > 16 {
		return false
	}
	if !strings.HasPrefix(phone, "+") {
		return false
	}
	for i, r := range phone {
		if i == 0 {
			continue
		}
		if !unicode.IsDigit(r) {
			return false
		}
	}
	return true
}

func parseFlexibleTimestamp(input string) (time.Time, error) {
	input = strings.TrimSpace(input)
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05.999999999",
		"2006-01-02T15:04:05.999999",
		"2006-01-02T15:04:05",
	}
	for _, layout := range layouts {
		t, err := time.Parse(layout, input)
		if err == nil {
			if layout == time.RFC3339Nano || layout == time.RFC3339 {
				return t.UTC(), nil
			}
			// Timestamp without zone is interpreted as UTC.
			return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC), nil
		}
	}
	return time.Time{}, errors.New("invalid timestamp format")
}

func userIDFromContext(r *http.Request) string {
	v := r.Context().Value(ctxUserIDKey)
	if v == nil {
		return ""
	}
	out, _ := v.(string)
	return out
}

func roleFromContext(r *http.Request) string {
	v := r.Context().Value(ctxRoleKey)
	if v == nil {
		return ""
	}
	out, _ := v.(string)
	return out
}

func (s *Server) enrichTravelerListing(in domain.TravelerListing) domain.TravelerListing {
	user, err := s.repo.GetUserByID(in.TravelerID)
	if err != nil {
		return in
	}
	in.TravelerName = user.FullName
	in.TravelerAvatar = user.AvatarURL
	return in
}

func (s *Server) enrichTravelerListings(in []domain.TravelerListing) []domain.TravelerListing {
	cache := map[string]domain.User{}
	for i := range in {
		id := in[i].TravelerID
		if id == "" {
			continue
		}
		user, ok := cache[id]
		if !ok {
			found, err := s.repo.GetUserByID(id)
			if err != nil {
				continue
			}
			cache[id] = found
			user = found
		}
		in[i].TravelerName = user.FullName
		in[i].TravelerAvatar = user.AvatarURL
	}
	return in
}

func (s *Server) enrichDeliveryRequest(in domain.DeliveryRequest) domain.DeliveryRequest {
	user, err := s.repo.GetUserByID(in.ClientID)
	if err != nil {
		return in
	}
	in.ClientName = user.FullName
	in.ClientAvatar = user.AvatarURL
	return in
}

func (s *Server) enrichDeliveryRequests(in []domain.DeliveryRequest) []domain.DeliveryRequest {
	cache := map[string]domain.User{}
	for i := range in {
		id := in[i].ClientID
		if id == "" {
			continue
		}
		user, ok := cache[id]
		if !ok {
			found, err := s.repo.GetUserByID(id)
			if err != nil {
				continue
			}
			cache[id] = found
			user = found
		}
		in[i].ClientName = user.FullName
		in[i].ClientAvatar = user.AvatarURL
	}
	return in
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]any{"error": msg, "timestamp": time.Now().UTC()})
}
