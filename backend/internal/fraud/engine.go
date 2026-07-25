package fraud

import (
	"strings"
	"time"

	"p2p-delivery/backend/internal/domain"
)

type Evaluation struct {
	Score   int
	Status  string
	Reasons []string
}

// EvaluateDeliveryRequestRisk scores a delivery request for fraud risk.
// Status thresholds: score >= 70 -> rejected_high_risk,
// 40 <= score < 70 -> pending_review, score < 40 -> open.
func EvaluateDeliveryRequestRisk(req domain.DeliveryRequest, previous []domain.DeliveryRequest) Evaluation {
	reasons := []string{}
	score := 0

	if req.DeclaredValue > 3000 {
		score += 35
		reasons = append(reasons, "high declared value")
	}
	if req.WeightKg > 20 {
		score += 10
		reasons = append(reasons, "very large package")
	}
	if strings.Contains(strings.ToLower(req.PackageDescription), "cash") ||
		strings.Contains(strings.ToLower(req.PackageDescription), "jewelry") ||
		strings.Contains(strings.ToLower(req.PackageDescription), "weapon") ||
		strings.Contains(strings.ToLower(req.PackageDescription), "drug") {
		score += 25
		reasons = append(reasons, "suspicious package contents")
	}
	if strings.HasPrefix(req.RecipientPhone, "+1") && req.DeclaredValue > 2000 {
		score += 15
		reasons = append(reasons, "high-value request with US phone prefix")
	}
	if len(previous) >= 3 {
		score += 15
		reasons = append(reasons, "burst of recent requests")
	}

	if len(previous) > 0 {
		recent := 0
		for _, p := range previous {
			if p.CreatedAt.IsZero() {
				continue
			}
			if time.Since(p.CreatedAt) <= 24*time.Hour {
				recent++
			}
		}
		if recent >= 2 {
			score += 10
			reasons = append(reasons, "multiple recent requests")
		}
	}

	switch {
	case score >= 70:
		return Evaluation{Score: score, Status: "rejected_high_risk", Reasons: reasons}
	case score >= 40:
		return Evaluation{Score: score, Status: "pending_review", Reasons: reasons}
	default:
		// FIX: low-risk requests must fall back to the normal "open" flow,
		// otherwise every request ends up stuck in manual review and the
		// duplicate-detection check in createDeliveryRequest (which only
		// looks at status == "open") never triggers.
		return Evaluation{Score: score, Status: "open", Reasons: reasons}
	}
}

// EvaluatePackageRisk scores a package-verification submission based on
// its declared contents, reusing the same keyword heuristic as delivery
// requests so both entry points stay consistent instead of duplicating
// ad hoc logic in the HTTP handler.
func EvaluatePackageRisk(declaredContents string) Evaluation {
	reasons := []string{}
	score := 10 // baseline: every submission awaits manual review

	lower := strings.ToLower(declaredContents)
	if strings.Contains(lower, "cash") ||
		strings.Contains(lower, "jewelry") ||
		strings.Contains(lower, "weapon") ||
		strings.Contains(lower, "drug") {
		score = 80
		reasons = append(reasons, "declared contents contain suspicious keyword")
	}

	status := "pending_review"
	if score >= 70 {
		status = "rejected_high_risk"
	}
	return Evaluation{Score: score, Status: status, Reasons: reasons}
}
