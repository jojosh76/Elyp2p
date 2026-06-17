package store

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"golang.org/x/crypto/bcrypt"
	"p2p-delivery/backend/internal/domain"
)

type PostgresStore struct {
	db *sql.DB
}

func NewPostgresStore(dsn string) (*PostgresStore, error) {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(30 * time.Minute)
	if err := db.Ping(); err != nil {
		return nil, err
	}
	return &PostgresStore{db: db}, nil
}

func (s *PostgresStore) Close() error {
	return s.db.Close()
}

func (s *PostgresStore) CreateUser(in domain.User) (domain.User, error) {
	const q = `
		INSERT INTO users (email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		RETURNING id::text, created_at
	`
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	err := s.db.QueryRow(q, in.Email, in.FullName, in.Role, in.PasswordHash, in.AvatarURL, in.Phone, in.Bio, in.PermanentAddress, in.PassportNumber, in.CountryOfResidence, in.KYCStatus, strings.TrimSpace(in.PayoutProvider), strings.TrimSpace(in.PayoutAccountID), strings.TrimSpace(in.PayoutAccountStatus)).
		Scan(&in.ID, &in.CreatedAt)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return domain.User{}, errors.New("email already exists")
		}
		return domain.User{}, err
	}
	return in, nil
}

func (s *PostgresStore) DeleteUserByID(id string) error {
	res, err := s.db.Exec(`DELETE FROM users WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return errors.New("user not found")
	}
	return nil
}

func (s *PostgresStore) GetUserByEmail(email string) (domain.User, error) {
	const q = `
		SELECT id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
		FROM users WHERE email = $1
	`
	var out domain.User
	err := s.db.QueryRow(q, strings.ToLower(strings.TrimSpace(email))).Scan(
		&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, errors.New("user not found")
		}
		return domain.User{}, err
	}
	return out, nil
}

func (s *PostgresStore) GetUserByID(id string) (domain.User, error) {
	const q = `
		SELECT id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
		FROM users WHERE id = $1::uuid
	`
	var out domain.User
	err := s.db.QueryRow(q, id).Scan(
		&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, errors.New("user not found")
		}
		return domain.User{}, err
	}
	return out, nil
}

func (s *PostgresStore) ListUsers() ([]domain.User, error) {
	rows, err := s.db.Query(`
		SELECT id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
		FROM users ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.User{}
	for rows.Next() {
		var u domain.User
		if err := rows.Scan(&u.ID, &u.Email, &u.FullName, &u.Role, &u.PasswordHash, &u.AvatarURL, &u.Phone, &u.Bio, &u.PermanentAddress, &u.PassportNumber, &u.CountryOfResidence, &u.KYCStatus, &u.PayoutProvider, &u.PayoutAccountID, &u.PayoutAccountStatus, &u.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (s *PostgresStore) UpdateUserProfile(in domain.User) (domain.User, error) {
	const q = `
		UPDATE users
		SET full_name = $2, avatar_url = $3, phone = $4, bio = $5, permanent_address = $6, country_of_residence = $7
		WHERE id = $1::uuid
		RETURNING id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
	`
	var out domain.User
	err := s.db.QueryRow(q, in.ID, strings.TrimSpace(in.FullName), strings.TrimSpace(in.AvatarURL), strings.TrimSpace(in.Phone), strings.TrimSpace(in.Bio), strings.TrimSpace(in.PermanentAddress), strings.TrimSpace(in.CountryOfResidence)).
		Scan(&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, errors.New("user not found")
		}
		return domain.User{}, err
	}
	return out, nil
}

func (s *PostgresStore) SetUserPayoutAccount(userID, provider, accountID, status string) (domain.User, error) {
	const q = `
		UPDATE users
		SET payout_provider = $2, payout_account_id = $3, payout_account_status = $4
		WHERE id = $1::uuid
		RETURNING id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
	`
	var out domain.User
	err := s.db.QueryRow(q, userID, strings.TrimSpace(provider), strings.TrimSpace(accountID), strings.TrimSpace(status)).
		Scan(&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, errors.New("user not found")
		}
		return domain.User{}, err
	}
	return out, nil
}

func (s *PostgresStore) SocialLogin(provider, providerUserID, email, fullName, avatarURL string) (domain.User, error) {
	provider = strings.ToLower(strings.TrimSpace(provider))
	providerUserID = strings.TrimSpace(providerUserID)
	email = strings.ToLower(strings.TrimSpace(email))
	fullName = strings.TrimSpace(fullName)
	avatarURL = strings.TrimSpace(avatarURL)
	if provider == "" || providerUserID == "" || email == "" {
		return domain.User{}, errors.New("provider, provider_user_id and email are required")
	}
	if fullName == "" {
		fullName = "Social User"
	}

	tx, err := s.db.Begin()
	if err != nil {
		return domain.User{}, err
	}
	defer tx.Rollback()

	var userID string
	err = tx.QueryRow(`SELECT user_id::text FROM social_accounts WHERE provider = $1 AND provider_user_id = $2`, provider, providerUserID).Scan(&userID)
	if err == nil {
		var out domain.User
		err = tx.QueryRow(`
			UPDATE users
			SET avatar_url = CASE WHEN $2 = '' THEN avatar_url ELSE $2 END
			WHERE id = $1::uuid
			RETURNING id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
		`, userID, avatarURL).Scan(&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt)
		if err != nil {
			return domain.User{}, err
		}
		if err := tx.Commit(); err != nil {
			return domain.User{}, err
		}
		return out, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, err
	}

	err = tx.QueryRow(`SELECT id::text FROM users WHERE email = $1`, email).Scan(&userID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return domain.User{}, err
	}
	if errors.Is(err, sql.ErrNoRows) {
		err = tx.QueryRow(`
			INSERT INTO users (email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status)
			VALUES ($1,$2,'client','', $3, '', '', '', '', '', 'unverified', '', '', '')
			RETURNING id::text
		`, email, fullName, avatarURL).Scan(&userID)
		if err != nil {
			return domain.User{}, err
		}
	}

	_, err = tx.Exec(`
		INSERT INTO social_accounts (user_id, provider, provider_user_id)
		VALUES ($1::uuid, $2, $3)
		ON CONFLICT (provider, provider_user_id) DO NOTHING
	`, userID, provider, providerUserID)
	if err != nil {
		return domain.User{}, err
	}

	var out domain.User
	err = tx.QueryRow(`
		UPDATE users
		SET avatar_url = CASE WHEN $2 = '' THEN avatar_url ELSE $2 END
		WHERE id = $1::uuid
		RETURNING id::text, email, full_name, role, password_hash, avatar_url, phone, bio, permanent_address, passport_number, country_of_residence, kyc_status, payout_provider, payout_account_id, payout_account_status, created_at
	`, userID, avatarURL).Scan(&out.ID, &out.Email, &out.FullName, &out.Role, &out.PasswordHash, &out.AvatarURL, &out.Phone, &out.Bio, &out.PermanentAddress, &out.PassportNumber, &out.CountryOfResidence, &out.KYCStatus, &out.PayoutProvider, &out.PayoutAccountID, &out.PayoutAccountStatus, &out.CreatedAt)
	if err != nil {
		return domain.User{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.User{}, err
	}
	return out, nil
}

func (s *PostgresStore) ListOAuthProviderConfigs() ([]domain.OAuthProviderConfig, error) {
	rows, err := s.db.Query(`
		SELECT provider, enabled, client_id, ios_client_id, web_client_id, updated_at
		FROM oauth_provider_configs
		ORDER BY provider ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []domain.OAuthProviderConfig{}
	for rows.Next() {
		var cfg domain.OAuthProviderConfig
		if err := rows.Scan(&cfg.Provider, &cfg.Enabled, &cfg.ClientID, &cfg.IOSClientID, &cfg.WebClientID, &cfg.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, cfg)
	}
	return out, rows.Err()
}

func (s *PostgresStore) UpsertOAuthProviderConfig(in domain.OAuthProviderConfig) (domain.OAuthProviderConfig, error) {
	provider := strings.ToLower(strings.TrimSpace(in.Provider))
	if provider != "google" && provider != "apple" {
		return domain.OAuthProviderConfig{}, errors.New("provider must be google or apple")
	}
	in.Provider = provider
	in.ClientID = strings.TrimSpace(in.ClientID)
	in.IOSClientID = strings.TrimSpace(in.IOSClientID)
	in.WebClientID = strings.TrimSpace(in.WebClientID)

	err := s.db.QueryRow(`
		INSERT INTO oauth_provider_configs (provider, enabled, client_id, ios_client_id, web_client_id, updated_at)
		VALUES ($1, $2, $3, $4, $5, NOW())
		ON CONFLICT (provider)
		DO UPDATE SET
			enabled = EXCLUDED.enabled,
			client_id = EXCLUDED.client_id,
			ios_client_id = EXCLUDED.ios_client_id,
			web_client_id = EXCLUDED.web_client_id,
			updated_at = NOW()
		RETURNING provider, enabled, client_id, ios_client_id, web_client_id, updated_at
	`, in.Provider, in.Enabled, in.ClientID, in.IOSClientID, in.WebClientID).
		Scan(&in.Provider, &in.Enabled, &in.ClientID, &in.IOSClientID, &in.WebClientID, &in.UpdatedAt)
	if err != nil {
		return domain.OAuthProviderConfig{}, err
	}
	return in, nil
}

func (s *PostgresStore) CreateOTPChallenge(userID, phone, purpose, code string, expiresAt time.Time) (string, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return "", errors.New("otp code is required")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	var id string
	err = s.db.QueryRow(`
		INSERT INTO otp_challenges (user_id, phone, purpose, code_hash, expires_at)
		VALUES ($1::uuid, $2, $3, $4, $5)
		RETURNING id::text
	`, userID, strings.TrimSpace(phone), strings.TrimSpace(purpose), string(hash), expiresAt.UTC()).Scan(&id)
	if err != nil {
		return "", err
	}
	return id, nil
}

func (s *PostgresStore) VerifyOTPChallenge(sessionID, code string) (domain.User, error) {
	var (
		userID     string
		codeHash   string
		expiresAt  time.Time
		verifiedAt sql.NullTime
	)
	err := s.db.QueryRow(`
		SELECT user_id::text, code_hash, expires_at, verified_at
		FROM otp_challenges
		WHERE id = $1::uuid
	`, strings.TrimSpace(sessionID)).Scan(&userID, &codeHash, &expiresAt, &verifiedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, errors.New("otp session not found")
		}
		return domain.User{}, err
	}
	if verifiedAt.Valid {
		return domain.User{}, errors.New("otp session already used")
	}
	if time.Now().UTC().After(expiresAt.UTC()) {
		return domain.User{}, errors.New("otp code expired")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(strings.TrimSpace(code))); err != nil {
		return domain.User{}, errors.New("invalid otp code")
	}
	if _, err := s.db.Exec(`UPDATE otp_challenges SET verified_at = NOW() WHERE id = $1::uuid`, strings.TrimSpace(sessionID)); err != nil {
		return domain.User{}, err
	}
	return s.GetUserByID(userID)
}

func (s *PostgresStore) CreateTravelerListing(in domain.TravelerListing) (domain.TravelerListing, error) {
	const q = `
		INSERT INTO traveler_listings (traveler_id, origin, destination_type, destination, departure_date, arrival_date, max_weight_kg, price_per_kg, status)
		VALUES ($1::uuid,$2,$3,$4,$5,$6,$7,$8,'open')
		RETURNING id::text, status, created_at
	`
	err := s.db.QueryRow(q, in.TravelerID, in.Origin, in.DestinationType, in.Destination, in.DepartureDate, in.ArrivalDate, in.MaxWeightKg, in.PricePerKg).
		Scan(&in.ID, &in.Status, &in.CreatedAt)
	if err != nil {
		return domain.TravelerListing{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListTravelerListings(destination string) ([]domain.TravelerListing, error) {
	base := `
		SELECT id::text, traveler_id::text, origin, destination_type, destination, departure_date, arrival_date, max_weight_kg, price_per_kg, status, created_at
		FROM traveler_listings
	`
	args := []any{}
	if destination != "" {
		base += ` WHERE destination ILIKE $1`
		args = append(args, destination)
	}
	base += ` ORDER BY created_at DESC`
	return scanTravelerListings(s.db.Query(base, args...))
}

func (s *PostgresStore) ListTravelerListingsByUser(userID string) ([]domain.TravelerListing, error) {
	return scanTravelerListings(s.db.Query(`
		SELECT id::text, traveler_id::text, origin, destination_type, destination, departure_date, arrival_date, max_weight_kg, price_per_kg, status, created_at
		FROM traveler_listings WHERE traveler_id = $1::uuid ORDER BY created_at DESC
	`, userID))
}

func (s *PostgresStore) GetTravelerListingByID(id string) (domain.TravelerListing, error) {
	var out domain.TravelerListing
	err := s.db.QueryRow(`
		SELECT id::text, traveler_id::text, origin, destination_type, destination, departure_date, arrival_date, max_weight_kg, price_per_kg, status, created_at
		FROM traveler_listings WHERE id = $1::uuid
	`, id).Scan(&out.ID, &out.TravelerID, &out.Origin, &out.DestinationType, &out.Destination, &out.DepartureDate, &out.ArrivalDate, &out.MaxWeightKg, &out.PricePerKg, &out.Status, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.TravelerListing{}, errors.New("listing not found")
		}
		return domain.TravelerListing{}, err
	}
	return out, nil
}

func scanTravelerListings(rows *sql.Rows, err error) ([]domain.TravelerListing, error) {
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.TravelerListing{}
	for rows.Next() {
		var it domain.TravelerListing
		if err := rows.Scan(&it.ID, &it.TravelerID, &it.Origin, &it.DestinationType, &it.Destination, &it.DepartureDate, &it.ArrivalDate, &it.MaxWeightKg, &it.PricePerKg, &it.Status, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (s *PostgresStore) CreateDeliveryRequest(in domain.DeliveryRequest) (domain.DeliveryRequest, error) {
	const q = `
		INSERT INTO delivery_requests (client_id, origin, destination_type, destination, recipient_name, recipient_phone, recipient_photo_url, dropoff_address, dropoff_instructions, weight_kg, package_description, declared_value, status)
		VALUES ($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'open')
		RETURNING id::text, status, created_at
	`
	err := s.db.QueryRow(q, in.ClientID, in.Origin, in.DestinationType, in.Destination, in.RecipientName, in.RecipientPhone, in.RecipientPhotoURL, in.DropoffAddress, in.DropoffInstructions, in.WeightKg, in.PackageDescription, in.DeclaredValue).
		Scan(&in.ID, &in.Status, &in.CreatedAt)
	if err != nil {
		return domain.DeliveryRequest{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListDeliveryRequests(destination string) ([]domain.DeliveryRequest, error) {
	base := `
		SELECT id::text, client_id::text, origin, destination_type, destination, recipient_name, recipient_phone, recipient_photo_url, dropoff_address, dropoff_instructions, weight_kg, package_description, declared_value, status, created_at
		FROM delivery_requests
	`
	args := []any{}
	if destination != "" {
		base += ` WHERE destination ILIKE $1`
		args = append(args, destination)
	}
	base += ` ORDER BY created_at DESC`
	return scanDeliveryRequests(s.db.Query(base, args...))
}

func (s *PostgresStore) ListDeliveryRequestsByUser(userID string) ([]domain.DeliveryRequest, error) {
	return scanDeliveryRequests(s.db.Query(`
		SELECT id::text, client_id::text, origin, destination_type, destination, recipient_name, recipient_phone, recipient_photo_url, dropoff_address, dropoff_instructions, weight_kg, package_description, declared_value, status, created_at
		FROM delivery_requests WHERE client_id = $1::uuid ORDER BY created_at DESC
	`, userID))
}

func (s *PostgresStore) GetDeliveryRequestByID(id string) (domain.DeliveryRequest, error) {
	var out domain.DeliveryRequest
	err := s.db.QueryRow(`
		SELECT id::text, client_id::text, origin, destination_type, destination, recipient_name, recipient_phone, recipient_photo_url, dropoff_address, dropoff_instructions, weight_kg, package_description, declared_value, status, created_at
		FROM delivery_requests
		WHERE id = $1::uuid
	`, id).Scan(&out.ID, &out.ClientID, &out.Origin, &out.DestinationType, &out.Destination, &out.RecipientName, &out.RecipientPhone, &out.RecipientPhotoURL, &out.DropoffAddress, &out.DropoffInstructions, &out.WeightKg, &out.PackageDescription, &out.DeclaredValue, &out.Status, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.DeliveryRequest{}, errors.New("request not found")
		}
		return domain.DeliveryRequest{}, err
	}
	return out, nil
}

func scanDeliveryRequests(rows *sql.Rows, err error) ([]domain.DeliveryRequest, error) {
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.DeliveryRequest{}
	for rows.Next() {
		var it domain.DeliveryRequest
		if err := rows.Scan(&it.ID, &it.ClientID, &it.Origin, &it.DestinationType, &it.Destination, &it.RecipientName, &it.RecipientPhone, &it.RecipientPhotoURL, &it.DropoffAddress, &it.DropoffInstructions, &it.WeightKg, &it.PackageDescription, &it.DeclaredValue, &it.Status, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (s *PostgresStore) CreateMatch(in domain.Match) (domain.Match, error) {
	var maxWeight float64
	var travelerID string
	err := s.db.QueryRow(`SELECT max_weight_kg, traveler_id::text FROM traveler_listings WHERE id = $1::uuid`, in.ListingID).Scan(&maxWeight, &travelerID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Match{}, errors.New("listing not found")
		}
		return domain.Match{}, err
	}

	var requestWeight float64
	var requestID string
	err = s.db.QueryRow(`SELECT weight_kg, id::text FROM delivery_requests WHERE id = $1::uuid`, in.RequestID).Scan(&requestWeight, &requestID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Match{}, errors.New("request not found")
		}
		return domain.Match{}, err
	}
	if requestWeight > maxWeight {
		return domain.Match{}, errors.New("request weight exceeds traveler max weight")
	}

	var kycStatus string
	if err := s.db.QueryRow(`SELECT kyc_status FROM users WHERE id = $1::uuid`, travelerID).Scan(&kycStatus); err != nil {
		return domain.Match{}, err
	}
	if kycStatus != "verified" {
		return domain.Match{}, errors.New("traveler must be KYC verified before match")
	}

	var packageOK bool
	if err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM package_verifications WHERE request_id = $1::uuid AND status = 'approved')`, requestID).Scan(&packageOK); err != nil {
		return domain.Match{}, err
	}
	if !packageOK {
		return domain.Match{}, errors.New("package must pass verification before match")
	}
	var duplicate bool
	if err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM matches WHERE listing_id = $1::uuid AND request_id = $2::uuid)`, in.ListingID, in.RequestID).Scan(&duplicate); err != nil {
		return domain.Match{}, err
	}
	if duplicate {
		return domain.Match{}, errors.New("a match already exists for this request and listing")
	}

	const q = `
		INSERT INTO matches (listing_id, request_id, agreed_price, estimated_delivery_at, status)
		VALUES ($1::uuid,$2::uuid,$3,$4,'matched')
		RETURNING id::text, estimated_delivery_at, status, created_at
	`
	err = s.db.QueryRow(q, in.ListingID, in.RequestID, in.AgreedPrice, in.EstimatedDeliveryAt).Scan(&in.ID, &in.EstimatedDeliveryAt, &in.Status, &in.CreatedAt)
	if err != nil {
		return domain.Match{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListMatchesByUser(userID string) ([]domain.Match, error) {
	rows, err := s.db.Query(`
		SELECT m.id::text, m.listing_id::text, m.request_id::text, m.agreed_price, m.estimated_delivery_at, m.status, m.created_at
		FROM matches m
		JOIN traveler_listings tl ON tl.id = m.listing_id
		JOIN delivery_requests dr ON dr.id = m.request_id
		WHERE tl.traveler_id = $1::uuid OR dr.client_id = $1::uuid
		ORDER BY m.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Match{}
	for rows.Next() {
		var m domain.Match
		if err := rows.Scan(&m.ID, &m.ListingID, &m.RequestID, &m.AgreedPrice, &m.EstimatedDeliveryAt, &m.Status, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *PostgresStore) GetMatchByID(id string) (domain.Match, error) {
	var out domain.Match
	err := s.db.QueryRow(`
		SELECT id::text, listing_id::text, request_id::text, agreed_price, estimated_delivery_at, status, created_at
		FROM matches
		WHERE id = $1::uuid
	`, id).Scan(&out.ID, &out.ListingID, &out.RequestID, &out.AgreedPrice, &out.EstimatedDeliveryAt, &out.Status, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Match{}, errors.New("match not found")
		}
		return domain.Match{}, err
	}
	return out, nil
}

func (s *PostgresStore) CreateEscrow(matchID, currency string, amount, commissionRate float64) (domain.Escrow, error) {
	var exists bool
	if err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM matches WHERE id = $1::uuid)`, matchID).Scan(&exists); err != nil {
		return domain.Escrow{}, err
	}
	if !exists {
		return domain.Escrow{}, errors.New("match not found")
	}
	if err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM escrows WHERE match_id = $1::uuid)`, matchID).Scan(&exists); err != nil {
		return domain.Escrow{}, err
	}
	if exists {
		return domain.Escrow{}, errors.New("escrow already exists for this match")
	}
	out := domain.Escrow{
		MatchID:          matchID,
		Currency:         currency,
		Amount:           amount,
		CommissionAmount: amount * commissionRate,
		TravelerAmount:   amount - (amount * commissionRate),
	}
	const q = `
		INSERT INTO escrows (match_id, currency, amount, commission_amount, traveler_amount, status)
		VALUES ($1::uuid,$2,$3,$4,$5,'pending_funding')
		RETURNING id::text, status, created_at
	`
	err := s.db.QueryRow(q, out.MatchID, out.Currency, out.Amount, out.CommissionAmount, out.TravelerAmount).
		Scan(&out.ID, &out.Status, &out.CreatedAt)
	if err != nil {
		return domain.Escrow{}, err
	}
	return out, nil
}

func (s *PostgresStore) DeleteEscrowByUser(id, userID string) error {
	res, err := s.db.Exec(`
		DELETE FROM escrows e
		USING matches m, traveler_listings tl, delivery_requests dr
		WHERE e.id = $1::uuid
		  AND m.id = e.match_id
		  AND tl.id = m.listing_id
		  AND dr.id = m.request_id
		  AND (tl.traveler_id = $2::uuid OR dr.client_id = $2::uuid)
	`, id, userID)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return errors.New("escrow not found")
	}
	return nil
}

func (s *PostgresStore) FundEscrow(id string) (domain.Escrow, error) {
	return s.updateEscrowState(id, `
		UPDATE escrows SET status='funded', funded_at=NOW() WHERE id=$1::uuid AND status='pending_funding'
		RETURNING id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
	`)
}

func (s *PostgresStore) ReleaseEscrow(id string) (domain.Escrow, error) {
	var (
		matchID string
		status  string
	)
	err := s.db.QueryRow(`SELECT match_id::text, status FROM escrows WHERE id = $1::uuid`, id).Scan(&matchID, &status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Escrow{}, errors.New("escrow not found")
		}
		return domain.Escrow{}, err
	}
	if status != "funded" {
		return domain.Escrow{}, errors.New("escrow must be funded first")
	}
	var delivered bool
	if err := s.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM tracking_events WHERE match_id = $1::uuid AND LOWER(status) = 'delivered')`, matchID).Scan(&delivered); err != nil {
		return domain.Escrow{}, err
	}
	if !delivered {
		return domain.Escrow{}, errors.New("release is locked until tracking status is delivered")
	}
	return s.updateEscrowState(id, `
		UPDATE escrows SET status='released', released_at=NOW() WHERE id=$1::uuid AND status='funded'
		RETURNING id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
	`)
}

func (s *PostgresStore) RefundEscrow(id string) (domain.Escrow, error) {
	return s.updateEscrowState(id, `
		UPDATE escrows
		SET status='refunded'
		WHERE id=$1::uuid AND status IN ('funded','disputed')
		RETURNING id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
	`)
}

func (s *PostgresStore) DisputeEscrow(id string) (domain.Escrow, error) {
	return s.updateEscrowState(id, `
		UPDATE escrows
		SET status='disputed'
		WHERE id=$1::uuid AND status='funded'
		RETURNING id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
	`)
}

func (s *PostgresStore) SetEscrowPayout(id, provider, reference, status string) (domain.Escrow, error) {
	return s.updateEscrowState(id, `
		UPDATE escrows
		SET payout_provider = $2,
		    payout_reference = $3,
		    payout_status = $4
		WHERE id=$1::uuid
		RETURNING id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
	`, provider, reference, status)
}

func (s *PostgresStore) updateEscrowState(id, query string, args ...any) (domain.Escrow, error) {
	var out domain.Escrow
	params := append([]any{id}, args...)
	err := s.db.QueryRow(query, params...).Scan(&out.ID, &out.MatchID, &out.Currency, &out.Amount, &out.CommissionAmount, &out.TravelerAmount, &out.Status, &out.FundedAt, &out.ReleasedAt, &out.PayoutStatus, &out.PayoutProvider, &out.PayoutReference, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Escrow{}, errors.New("escrow not found or invalid state")
		}
		return domain.Escrow{}, err
	}
	return out, nil
}

func (s *PostgresStore) ListEscrows() ([]domain.Escrow, error) {
	return scanEscrows(s.db.Query(`
		SELECT id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
		FROM escrows ORDER BY created_at DESC
	`))
}

func (s *PostgresStore) ListEscrowsByUser(userID string) ([]domain.Escrow, error) {
	return scanEscrows(s.db.Query(`
		SELECT e.id::text, e.match_id::text, e.currency, e.amount, e.commission_amount, e.traveler_amount, e.status, e.funded_at, e.released_at, e.payout_status, e.payout_provider, e.payout_reference, e.created_at
		FROM escrows e
		JOIN matches m ON m.id = e.match_id
		JOIN traveler_listings tl ON tl.id = m.listing_id
		JOIN delivery_requests dr ON dr.id = m.request_id
		WHERE tl.traveler_id = $1::uuid OR dr.client_id = $1::uuid
		ORDER BY e.created_at DESC
	`, userID))
}

func (s *PostgresStore) GetEscrowByID(id string) (domain.Escrow, error) {
	var out domain.Escrow
	err := s.db.QueryRow(`
		SELECT id::text, match_id::text, currency, amount, commission_amount, traveler_amount, status, funded_at, released_at, payout_status, payout_provider, payout_reference, created_at
		FROM escrows
		WHERE id = $1::uuid
	`, id).Scan(&out.ID, &out.MatchID, &out.Currency, &out.Amount, &out.CommissionAmount, &out.TravelerAmount, &out.Status, &out.FundedAt, &out.ReleasedAt, &out.PayoutStatus, &out.PayoutProvider, &out.PayoutReference, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Escrow{}, errors.New("escrow not found")
		}
		return domain.Escrow{}, err
	}
	return out, nil
}

func scanEscrows(rows *sql.Rows, err error) ([]domain.Escrow, error) {
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Escrow{}
	for rows.Next() {
		var e domain.Escrow
		if err := rows.Scan(&e.ID, &e.MatchID, &e.Currency, &e.Amount, &e.CommissionAmount, &e.TravelerAmount, &e.Status, &e.FundedAt, &e.ReleasedAt, &e.PayoutStatus, &e.PayoutProvider, &e.PayoutReference, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *PostgresStore) GetCommissionSummary() (domain.CommissionSummary, error) {
	var out domain.CommissionSummary
	err := s.db.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(amount),0), COALESCE(SUM(commission_amount),0)
		FROM escrows WHERE status = 'released'
	`).Scan(&out.ReleasedEscrows, &out.TotalVolume, &out.TotalCommission)
	if err != nil {
		return domain.CommissionSummary{}, err
	}
	return out, nil
}

func (s *PostgresStore) CreateKYCVerification(in domain.KYCVerification) (domain.KYCVerification, error) {
	var exists bool
	if err := s.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM kyc_verifications
			WHERE user_id = $1::uuid AND status IN ('pending_review','verified')
		)
	`, in.UserID).Scan(&exists); err != nil {
		return domain.KYCVerification{}, err
	}
	if exists {
		return domain.KYCVerification{}, errors.New("kyc is already submitted for this user")
	}
	const q = `
		INSERT INTO kyc_verifications (user_id, document_type, document_reference, address_proof_ref, status, review_notes)
		VALUES ($1::uuid,$2,$3,$4,'pending_review',$5)
		RETURNING id::text, status, created_at
	`
	err := s.db.QueryRow(q, in.UserID, in.DocumentType, in.DocumentReference, in.AddressProofRef, in.ReviewNotes).Scan(&in.ID, &in.Status, &in.CreatedAt)
	if err != nil {
		return domain.KYCVerification{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListKYCVerifications(status, userID string) ([]domain.KYCVerification, error) {
	base := `
		SELECT id::text, user_id::text, document_type, document_reference, address_proof_ref, status, review_notes, created_at
		FROM kyc_verifications WHERE 1=1
	`
	args := []any{}
	if status != "" {
		args = append(args, status)
		base += fmt.Sprintf(" AND status = $%d", len(args))
	}
	if userID != "" {
		args = append(args, userID)
		base += fmt.Sprintf(" AND user_id = $%d::uuid", len(args))
	}
	base += ` ORDER BY created_at DESC`

	rows, err := s.db.Query(base, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.KYCVerification{}
	for rows.Next() {
		var k domain.KYCVerification
		if err := rows.Scan(&k.ID, &k.UserID, &k.DocumentType, &k.DocumentReference, &k.AddressProofRef, &k.Status, &k.ReviewNotes, &k.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, k)
	}
	return out, rows.Err()
}

func (s *PostgresStore) ReviewKYCVerification(id, status, notes string) (domain.KYCVerification, error) {
	if status != "verified" && status != "rejected" {
		return domain.KYCVerification{}, errors.New("status must be verified or rejected")
	}
	tx, err := s.db.Begin()
	if err != nil {
		return domain.KYCVerification{}, err
	}
	defer tx.Rollback()

	var out domain.KYCVerification
	err = tx.QueryRow(`
		UPDATE kyc_verifications
		SET status = $2, review_notes = $3
		WHERE id = $1::uuid
		RETURNING id::text, user_id::text, document_type, document_reference, address_proof_ref, status, review_notes, created_at
	`, id, status, notes).Scan(&out.ID, &out.UserID, &out.DocumentType, &out.DocumentReference, &out.AddressProofRef, &out.Status, &out.ReviewNotes, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.KYCVerification{}, errors.New("kyc verification not found")
		}
		return domain.KYCVerification{}, err
	}
	if _, err := tx.Exec(`UPDATE users SET kyc_status = $2 WHERE id = $1::uuid`, out.UserID, status); err != nil {
		return domain.KYCVerification{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.KYCVerification{}, err
	}
	return out, nil
}

func (s *PostgresStore) CreatePackageVerification(in domain.PackageVerification) (domain.PackageVerification, error) {
	var exists bool
	if err := s.db.QueryRow(`
		SELECT EXISTS(
			SELECT 1 FROM package_verifications
			WHERE request_id = $1::uuid AND status IN ('pending_review','approved')
		)
	`, in.RequestID).Scan(&exists); err != nil {
		return domain.PackageVerification{}, err
	}
	if exists {
		return domain.PackageVerification{}, errors.New("package verification already exists for this request")
	}
	status := "pending_review"
	if in.RiskScore >= 70 {
		status = "rejected_high_risk"
	}
	const q = `
		INSERT INTO package_verifications (request_id, declared_contents, receipt_ref, screening_method, risk_score, status, review_notes)
		VALUES ($1::uuid,$2,$3,$4,$5,$6,$7)
		RETURNING id::text, status, created_at
	`
	err := s.db.QueryRow(q, in.RequestID, in.DeclaredContents, in.ReceiptRef, in.ScreeningMethod, in.RiskScore, status, in.ReviewNotes).Scan(&in.ID, &in.Status, &in.CreatedAt)
	if err != nil {
		return domain.PackageVerification{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListPackageVerifications(status, requestID string) ([]domain.PackageVerification, error) {
	base := `
		SELECT id::text, request_id::text, declared_contents, receipt_ref, screening_method, risk_score, status, review_notes, created_at
		FROM package_verifications WHERE 1=1
	`
	args := []any{}
	if status != "" {
		args = append(args, status)
		base += fmt.Sprintf(" AND status = $%d", len(args))
	}
	if requestID != "" {
		args = append(args, requestID)
		base += fmt.Sprintf(" AND request_id = $%d::uuid", len(args))
	}
	base += ` ORDER BY created_at DESC`
	rows, err := s.db.Query(base, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.PackageVerification{}
	for rows.Next() {
		var p domain.PackageVerification
		if err := rows.Scan(&p.ID, &p.RequestID, &p.DeclaredContents, &p.ReceiptRef, &p.ScreeningMethod, &p.RiskScore, &p.Status, &p.ReviewNotes, &p.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *PostgresStore) ReviewPackageVerification(id, status, notes string) (domain.PackageVerification, error) {
	switch status {
	case "approved", "rejected", "rejected_high_risk":
	default:
		return domain.PackageVerification{}, errors.New("invalid package verification status")
	}
	var out domain.PackageVerification
	err := s.db.QueryRow(`
		UPDATE package_verifications
		SET status = $2, review_notes = $3
		WHERE id = $1::uuid
		RETURNING id::text, request_id::text, declared_contents, receipt_ref, screening_method, risk_score, status, review_notes, created_at
	`, id, status, notes).Scan(&out.ID, &out.RequestID, &out.DeclaredContents, &out.ReceiptRef, &out.ScreeningMethod, &out.RiskScore, &out.Status, &out.ReviewNotes, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.PackageVerification{}, errors.New("package verification not found")
		}
		return domain.PackageVerification{}, err
	}
	return out, nil
}

func (s *PostgresStore) AddTrackingEvent(in domain.TrackingEvent) (domain.TrackingEvent, error) {
	const q = `
		INSERT INTO tracking_events (match_id, status, location, notes, occurred_at)
		VALUES ($1::uuid,$2,$3,$4,$5)
		RETURNING id::text, occurred_at, created_at
	`
	if in.OccurredAt == nil {
		t := time.Now().UTC()
		in.OccurredAt = &t
	}
	if err := s.db.QueryRow(q, in.MatchID, in.Status, in.Location, in.Notes, in.OccurredAt).Scan(&in.ID, &in.OccurredAt, &in.CreatedAt); err != nil {
		return domain.TrackingEvent{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListTrackingEvents(matchID string) ([]domain.TrackingEvent, error) {
	rows, err := s.db.Query(`
		SELECT id::text, match_id::text, status, location, notes, occurred_at, created_at
		FROM tracking_events WHERE match_id = $1::uuid ORDER BY created_at ASC
	`, matchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.TrackingEvent{}
	for rows.Next() {
		var t domain.TrackingEvent
		if err := rows.Scan(&t.ID, &t.MatchID, &t.Status, &t.Location, &t.Notes, &t.OccurredAt, &t.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *PostgresStore) CreateNotification(in domain.Notification) (domain.Notification, error) {
	const q = `
		INSERT INTO notifications (user_id, title, message, type)
		VALUES ($1::uuid,$2,$3,$4)
		RETURNING id::text, created_at, read_at
	`
	if err := s.db.QueryRow(q, in.UserID, in.Title, in.Message, in.Type).Scan(&in.ID, &in.CreatedAt, &in.ReadAt); err != nil {
		return domain.Notification{}, err
	}
	return in, nil
}

func (s *PostgresStore) ListNotificationsByUser(userID string) ([]domain.Notification, error) {
	rows, err := s.db.Query(`
		SELECT id::text, user_id::text, title, message, type, read_at, created_at
		FROM notifications
		WHERE user_id = $1::uuid
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []domain.Notification{}
	for rows.Next() {
		var n domain.Notification
		if err := rows.Scan(&n.ID, &n.UserID, &n.Title, &n.Message, &n.Type, &n.ReadAt, &n.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func (s *PostgresStore) MarkNotificationRead(id, userID string) (domain.Notification, error) {
	var out domain.Notification
	err := s.db.QueryRow(`
		UPDATE notifications
		SET read_at = NOW()
		WHERE id = $1::uuid AND user_id = $2::uuid
		RETURNING id::text, user_id::text, title, message, type, read_at, created_at
	`, id, userID).Scan(&out.ID, &out.UserID, &out.Title, &out.Message, &out.Type, &out.ReadAt, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Notification{}, errors.New("notification not found")
		}
		return domain.Notification{}, err
	}
	return out, nil
}

func (s *PostgresStore) DeleteNotification(id, userID string) error {
	res, err := s.db.Exec(`DELETE FROM notifications WHERE id = $1::uuid AND user_id = $2::uuid`, id, userID)
	if err != nil {
		return err
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if affected == 0 {
		return errors.New("notification not found")
	}
	return nil
}

func (s *PostgresStore) CreatePaymentEvent(in domain.PaymentEvent) (domain.PaymentEvent, error) {
	const q = `
		INSERT INTO payment_events (provider, provider_event_id, event_type, payload)
		VALUES ($1,$2,$3,$4)
		RETURNING id::text, created_at
	`
	in.Provider = strings.ToLower(strings.TrimSpace(in.Provider))
	in.ProviderEventID = strings.TrimSpace(in.ProviderEventID)
	in.EventType = strings.TrimSpace(in.EventType)
	if in.Provider == "" || in.ProviderEventID == "" {
		return domain.PaymentEvent{}, errors.New("provider and provider_event_id are required")
	}
	if err := s.db.QueryRow(q, in.Provider, in.ProviderEventID, in.EventType, in.Payload).Scan(&in.ID, &in.CreatedAt); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return domain.PaymentEvent{}, errors.New("payment event already exists")
		}
		return domain.PaymentEvent{}, err
	}
	return in, nil
}

func (s *PostgresStore) GetPaymentEventByProviderEventID(provider, providerEventID string) (domain.PaymentEvent, error) {
	var out domain.PaymentEvent
	err := s.db.QueryRow(`
		SELECT id::text, provider, provider_event_id, event_type, payload, created_at
		FROM payment_events
		WHERE provider = $1 AND provider_event_id = $2
	`, strings.ToLower(strings.TrimSpace(provider)), strings.TrimSpace(providerEventID)).
		Scan(&out.ID, &out.Provider, &out.ProviderEventID, &out.EventType, &out.Payload, &out.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.PaymentEvent{}, errors.New("payment event not found")
		}
		return domain.PaymentEvent{}, err
	}
	return out, nil
}

func (s *PostgresStore) RunMigrations() error {
	migrationDir, err := findMigrationDir()
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(migrationDir)
	if err != nil {
		return fmt.Errorf("failed to read migrations directory: %w", err)
	}
	files := []string{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := strings.ToLower(strings.TrimSpace(entry.Name()))
		if strings.HasSuffix(name, ".sql") {
			files = append(files, entry.Name())
		}
	}
	sort.Strings(files)
	if len(files) == 0 {
		return errors.New("no migration files found")
	}
	for _, file := range files {
		path := filepath.Join(migrationDir, file)
		sqlBytes, readErr := os.ReadFile(path)
		if readErr != nil {
			return fmt.Errorf("failed to read migration %s: %w", file, readErr)
		}
		if _, execErr := s.db.Exec(string(sqlBytes)); execErr != nil {
			return fmt.Errorf("migration %s failed: %w", file, execErr)
		}
	}
	return nil
}

func findMigrationDir() (string, error) {
	candidates := []string{
		filepath.Join("migrations"),
		filepath.Join("backend", "migrations"),
	}
	_, thisFile, _, ok := runtime.Caller(0)
	if ok {
		storeDir := filepath.Dir(thisFile)
		candidates = append(candidates, filepath.Clean(filepath.Join(storeDir, "..", "..", "migrations")))
	}
	for _, candidate := range candidates {
		info, err := os.Stat(candidate)
		if err == nil && info.IsDir() {
			return candidate, nil
		}
	}
	return "", errors.New("migrations directory not found")
}
