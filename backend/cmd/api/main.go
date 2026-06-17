package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"p2p-delivery/backend/internal/auth"
	httpapi "p2p-delivery/backend/internal/http"
	"p2p-delivery/backend/internal/payments"
	"p2p-delivery/backend/internal/store"
)

func main() {
	addr := getenv("API_ADDR", ":8080")
	commissionRate := getenvFloat("COMMISSION_RATE", 0.10)
	jwtSecret := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	allowInsecureDev := getenvBool("ALLOW_INSECURE_DEV", false)
	if jwtSecret == "" {
		if !allowInsecureDev {
			log.Fatal("JWT_SECRET must be set in non-dev environments")
		}
		jwtSecret = "change-me-in-production"
	}
	if jwtSecret == "change-me-in-production" && !allowInsecureDev {
		log.Fatal("JWT_SECRET is using insecure default; set a strong secret")
	}
	tokenTTL := getenvDuration("JWT_TTL", 72*time.Hour)
	otpTTL := getenvDuration("OTP_TTL", 5*time.Minute)
	otpDevMode := getenvBool("OTP_DEV_MODE", false)
	twilioSID := getenv("TWILIO_ACCOUNT_SID", "")
	twilioToken := getenv("TWILIO_AUTH_TOKEN", "")
	twilioFrom := getenv("TWILIO_FROM_NUMBER", "")
	uploadSecret := getenv("UPLOAD_SIGNING_SECRET", jwtSecret)
	uploadDir := getenv("UPLOADS_DIR", "data/uploads")
	uploadTokenTTL := getenvDuration("UPLOAD_TOKEN_TTL", 15*time.Minute)
	authMaxFails := getenvInt("AUTH_MAX_FAILS", 5)
	authLockWindow := getenvDuration("AUTH_LOCK_WINDOW", 15*time.Minute)
	otpMaxFails := getenvInt("OTP_MAX_FAILS", 5)
	otpLockWindow := getenvDuration("OTP_LOCK_WINDOW", 15*time.Minute)
	paymentProviderName := getenv("PAYMENT_PROVIDER", "noop")
	dbURL := os.Getenv("DATABASE_URL")
	var repo store.Repository
	if dbURL == "" {
		log.Printf("DATABASE_URL not set; using in-memory store")
		repo = store.NewMemoryStore()
	} else {
		pg, err := store.NewPostgresStore(dbURL)
		if err != nil {
			log.Fatalf("failed to connect database: %v", err)
		}
		defer pg.Close()
		if err := pg.RunMigrations(); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
		repo = pg
	}

	authManager := auth.NewManager(jwtSecret, tokenTTL)
	server := httpapi.NewServer(
		repo,
		authManager,
		commissionRate,
		otpTTL,
		otpDevMode,
		twilioSID,
		twilioToken,
		twilioFrom,
		uploadSecret,
		uploadDir,
		uploadTokenTTL,
		authMaxFails,
		authLockWindow,
		otpMaxFails,
		otpLockWindow,
	)
	paymentProvider, err := payments.BuildProvider(paymentProviderName)
	if err != nil {
		log.Fatalf("failed to configure payment provider: %v", err)
	}
	server.SetPaymentProvider(paymentProvider)

	httpServer := &http.Server{
		Addr:              addr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("p2p delivery api listening on %s with commission rate %.2f%% (payments=%s)", addr, commissionRate*100, paymentProviderName)
	if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func getenv(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func getenvFloat(key string, fallback float64) float64 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return fallback
	}
	return f
}

func getenvDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}

func getenvBool(key string, fallback bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if v == "" {
		return fallback
	}
	switch v {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func getenvInt(key string, fallback int) int {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}
