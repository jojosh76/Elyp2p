package fraud

import (
	"testing"
	"time"

	"p2p-delivery/backend/internal/domain"
)

func TestEvaluateDeliveryRequestRiskFlagsSuspiciousRequests(t *testing.T) {
	req := domain.DeliveryRequest{
		ID:                 "req-1",
		DeclaredValue:      4800,
		WeightKg:           1.2,
		PackageDescription: "cash and jewelry for urgent handoff",
		RecipientPhone:     "+1234567890",
	}
	previous := []domain.DeliveryRequest{
		{ID: "req-2", Status: "open", CreatedAt: time.Now().UTC().Add(-2 * time.Hour)},
		{ID: "req-3", Status: "open", CreatedAt: time.Now().UTC().Add(-3 * time.Hour)},
		{ID: "req-4", Status: "open", CreatedAt: time.Now().UTC().Add(-4 * time.Hour)},
	}

	result := EvaluateDeliveryRequestRisk(req, previous)
	if result.Score < 70 {
		t.Fatalf("expected high risk score, got %d", result.Score)
	}
	if result.Status != "rejected_high_risk" {
		t.Fatalf("expected high-risk status, got %s", result.Status)
	}
	if len(result.Reasons) == 0 {
		t.Fatal("expected fraud reasons to be reported")
	}
}

func TestEvaluateDeliveryRequestRiskAllowsNormalRequests(t *testing.T) {
	req := domain.DeliveryRequest{
		ID:                 "req-5",
		DeclaredValue:      120,
		WeightKg:           8,
		PackageDescription: "books and office supplies",
		RecipientPhone:     "+2348090000000",
	}
	previous := []domain.DeliveryRequest{{
		ID:        "req-6",
		Status:    "completed",
		CreatedAt: time.Now().UTC().Add(-48 * time.Hour),
	}}

	result := EvaluateDeliveryRequestRisk(req, previous)
	if result.Score >= 40 {
		t.Fatalf("expected low risk score, got %d", result.Score)
	}
	// Low-risk requests must go through the normal flow, not manual review.
	if result.Status != "open" {
		t.Fatalf("expected open status for low-risk request, got %s", result.Status)
	}
}

func TestEvaluateDeliveryRequestRiskFlagsMediumRiskForReview(t *testing.T) {
	req := domain.DeliveryRequest{
		ID:                 "req-7",
		DeclaredValue:      3500, // > 3000 -> +35
		WeightKg:           5,
		PackageDescription: "electronics",
		RecipientPhone:     "+2348090000000",
	}
	previous := []domain.DeliveryRequest{
		{ID: "req-8", Status: "open", CreatedAt: time.Now().UTC().Add(-72 * time.Hour)},
		{ID: "req-9", Status: "open", CreatedAt: time.Now().UTC().Add(-72 * time.Hour)},
		{ID: "req-10", Status: "open", CreatedAt: time.Now().UTC().Add(-72 * time.Hour)}, // burst -> +15
	}

	result := EvaluateDeliveryRequestRisk(req, previous)
	if result.Score < 40 || result.Score >= 70 {
		t.Fatalf("expected medium risk score (40-69), got %d", result.Score)
	}
	if result.Status != "pending_review" {
		t.Fatalf("expected pending_review status, got %s", result.Status)
	}
}

func TestEvaluatePackageRiskFlagsSuspiciousContent(t *testing.T) {
	result := EvaluatePackageRisk("gold jewelry and cash")
	if result.Status != "rejected_high_risk" {
		t.Fatalf("expected rejected_high_risk, got %s", result.Status)
	}
}

func TestEvaluatePackageRiskAllowsNormalContent(t *testing.T) {
	result := EvaluatePackageRisk("books and clothes")
	if result.Status != "pending_review" {
		t.Fatalf("expected pending_review for normal contents, got %s", result.Status)
	}
	if result.Score >= 70 {
		t.Fatalf("expected low score for normal contents, got %d", result.Score)
	}
}
