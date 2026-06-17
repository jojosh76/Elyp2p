package store

import (
	"time"

	"p2p-delivery/backend/internal/domain"
)

type Repository interface {
	CreateUser(in domain.User) (domain.User, error)
	DeleteUserByID(id string) error
	GetUserByEmail(email string) (domain.User, error)
	GetUserByID(id string) (domain.User, error)
	ListUsers() ([]domain.User, error)
	UpdateUserProfile(in domain.User) (domain.User, error)
	SetUserPayoutAccount(userID, provider, accountID, status string) (domain.User, error)
	SocialLogin(provider, providerUserID, email, fullName, avatarURL string) (domain.User, error)
	CreateOTPChallenge(userID, phone, purpose, code string, expiresAt time.Time) (string, error)
	VerifyOTPChallenge(sessionID, code string) (domain.User, error)
	ListOAuthProviderConfigs() ([]domain.OAuthProviderConfig, error)
	UpsertOAuthProviderConfig(in domain.OAuthProviderConfig) (domain.OAuthProviderConfig, error)

	CreateTravelerListing(in domain.TravelerListing) (domain.TravelerListing, error)
	ListTravelerListings(destination string) ([]domain.TravelerListing, error)
	ListTravelerListingsByUser(userID string) ([]domain.TravelerListing, error)
	GetTravelerListingByID(id string) (domain.TravelerListing, error)

	CreateDeliveryRequest(in domain.DeliveryRequest) (domain.DeliveryRequest, error)
	ListDeliveryRequests(destination string) ([]domain.DeliveryRequest, error)
	ListDeliveryRequestsByUser(userID string) ([]domain.DeliveryRequest, error)
	GetDeliveryRequestByID(id string) (domain.DeliveryRequest, error)

	CreateMatch(in domain.Match) (domain.Match, error)
	ListMatchesByUser(userID string) ([]domain.Match, error)
	GetMatchByID(id string) (domain.Match, error)
	CreateEscrow(matchID, currency string, amount, commissionRate float64) (domain.Escrow, error)
	DeleteEscrowByUser(id, userID string) error
	FundEscrow(id string) (domain.Escrow, error)
	ReleaseEscrow(id string) (domain.Escrow, error)
	RefundEscrow(id string) (domain.Escrow, error)
	DisputeEscrow(id string) (domain.Escrow, error)
	SetEscrowPayout(id, provider, reference, status string) (domain.Escrow, error)
	ListEscrows() ([]domain.Escrow, error)
	ListEscrowsByUser(userID string) ([]domain.Escrow, error)
	GetEscrowByID(id string) (domain.Escrow, error)
	GetCommissionSummary() (domain.CommissionSummary, error)

	CreateKYCVerification(in domain.KYCVerification) (domain.KYCVerification, error)
	ListKYCVerifications(status, userID string) ([]domain.KYCVerification, error)
	ReviewKYCVerification(id, status, notes string) (domain.KYCVerification, error)
	CreatePackageVerification(in domain.PackageVerification) (domain.PackageVerification, error)
	ListPackageVerifications(status, requestID string) ([]domain.PackageVerification, error)
	ReviewPackageVerification(id, status, notes string) (domain.PackageVerification, error)

	AddTrackingEvent(in domain.TrackingEvent) (domain.TrackingEvent, error)
	ListTrackingEvents(matchID string) ([]domain.TrackingEvent, error)

	CreateNotification(in domain.Notification) (domain.Notification, error)
	ListNotificationsByUser(userID string) ([]domain.Notification, error)
	MarkNotificationRead(id, userID string) (domain.Notification, error)
	DeleteNotification(id, userID string) error
	CreatePaymentEvent(in domain.PaymentEvent) (domain.PaymentEvent, error)
	GetPaymentEventByProviderEventID(provider, providerEventID string) (domain.PaymentEvent, error)
}
