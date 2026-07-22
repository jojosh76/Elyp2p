package recommendations

import (
	"math"
	"sort"
	"strings"
	"time"

	"p2p-delivery/backend/internal/domain"
)

type MatchRecommendation struct {
	Listing               domain.TravelerListing `json:"listing"`
	Request               domain.DeliveryRequest `json:"request"`
	Score                 int                    `json:"score"`
	AcceptanceProbability int                    `json:"acceptance_probability"`
	SuggestedPrice        float64                `json:"suggested_price"`
	Reasons               []string               `json:"reasons"`
	Feasible              bool                   `json:"feasible"`
}

func ForRequest(request domain.DeliveryRequest, listings []domain.TravelerListing, now time.Time) []MatchRecommendation {
	out := make([]MatchRecommendation, 0, len(listings))
	for _, listing := range listings {
		out = append(out, Score(listing, request, now))
	}
	sortRecommendations(out)
	return out
}

func ForListing(listing domain.TravelerListing, requests []domain.DeliveryRequest, now time.Time) []MatchRecommendation {
	out := make([]MatchRecommendation, 0, len(requests))
	for _, request := range requests {
		out = append(out, Score(listing, request, now))
	}
	sortRecommendations(out)
	return out
}

func Score(listing domain.TravelerListing, request domain.DeliveryRequest, now time.Time) MatchRecommendation {
	score := 0
	reasons := []string{}
	feasible := true

	if equalPlace(listing.Destination, request.Destination) {
		score += 35
		reasons = append(reasons, "Destination match")
	} else if compatibleCountryMatch(listing, request) {
		score += 24
		reasons = append(reasons, "Destination country compatible")
	} else {
		feasible = false
		reasons = append(reasons, "Destination mismatch")
	}

	if equalPlace(listing.Origin, request.Origin) {
		score += 16
		reasons = append(reasons, "Origin match")
	}

	if listing.MaxWeightKg > 0 && request.WeightKg > 0 && request.WeightKg <= listing.MaxWeightKg {
		ratio := request.WeightKg / listing.MaxWeightKg
		switch {
		case ratio >= 0.25 && ratio <= 0.85:
			score += 18
			reasons = append(reasons, "Good capacity fit")
		case ratio < 0.25:
			score += 13
			reasons = append(reasons, "Light package")
		default:
			score += 10
			reasons = append(reasons, "Capacity is tight")
		}
	} else {
		feasible = false
		reasons = append(reasons, "Package exceeds traveler capacity")
	}

	if !listing.ArrivalDate.IsZero() {
		if listing.ArrivalDate.Before(now) {
			feasible = false
			reasons = append(reasons, "Traveler arrival is in the past")
		} else {
			hoursUntilArrival := listing.ArrivalDate.Sub(now).Hours()
			switch {
			case hoursUntilArrival <= 72:
				score += 18
				reasons = append(reasons, "Fast delivery window")
			case hoursUntilArrival <= 24*7:
				score += 13
				reasons = append(reasons, "Near delivery window")
			case hoursUntilArrival <= 24*21:
				score += 8
				reasons = append(reasons, "Acceptable delivery window")
			default:
				score += 4
			}
		}
	}

	if request.DeclaredValue <= 250 {
		score += 8
		reasons = append(reasons, "Low declared value risk")
	} else if request.DeclaredValue <= 1000 {
		score += 5
	}

	score += 5
	if !feasible && score > 55 {
		score = 55
	}
	score = clampInt(score, 0, 100)

	return MatchRecommendation{
		Listing:               listing,
		Request:               request,
		Score:                 score,
		AcceptanceProbability: acceptanceProbability(score, feasible),
		SuggestedPrice:        SuggestedPrice(listing, request, now),
		Reasons:               reasons,
		Feasible:              feasible,
	}
}

func SuggestedPrice(listing domain.TravelerListing, request domain.DeliveryRequest, now time.Time) float64 {
	base := listing.PricePerKg * request.WeightKg
	if base <= 0 {
		base = 10
	}
	multiplier := 1.0

	if !listing.ArrivalDate.IsZero() {
		hoursUntilArrival := listing.ArrivalDate.Sub(now).Hours()
		switch {
		case hoursUntilArrival <= 48:
			multiplier += 0.18
		case hoursUntilArrival <= 24*7:
			multiplier += 0.08
		case hoursUntilArrival > 24*21:
			multiplier -= 0.06
		}
	}

	if request.WeightKg > 0 && listing.MaxWeightKg > 0 {
		ratio := request.WeightKg / listing.MaxWeightKg
		if ratio > 0.75 {
			multiplier += 0.12
		} else if ratio < 0.20 {
			multiplier -= 0.05
		}
	}

	if request.DeclaredValue > 500 {
		multiplier += 0.06
	}
	if request.DeclaredValue > 1500 {
		multiplier += 0.08
	}

	return math.Round(base*multiplier*100) / 100
}

func sortRecommendations(in []MatchRecommendation) {
	sort.Slice(in, func(i, j int) bool {
		if in[i].Feasible != in[j].Feasible {
			return in[i].Feasible
		}
		if in[i].Score != in[j].Score {
			return in[i].Score > in[j].Score
		}
		return in[i].SuggestedPrice < in[j].SuggestedPrice
	})
}

func acceptanceProbability(score int, feasible bool) int {
	if !feasible {
		return clampInt(score/2, 0, 45)
	}
	return clampInt(20+int(float64(score)*0.75), 0, 95)
}

func equalPlace(a, b string) bool {
	return normalizePlace(a) == normalizePlace(b)
}

func compatibleCountryMatch(listing domain.TravelerListing, request domain.DeliveryRequest) bool {
	if listing.DestinationType != domain.DestinationCountry && request.DestinationType != domain.DestinationCountry {
		return false
	}
	a := normalizePlace(listing.Destination)
	b := normalizePlace(request.Destination)
	return a != "" && b != "" && (strings.Contains(a, b) || strings.Contains(b, a))
}

func normalizePlace(in string) string {
	out := strings.ToLower(strings.TrimSpace(in))
	out = strings.ReplaceAll(out, ".", "")
	out = strings.Join(strings.Fields(out), " ")
	return out
}

func clampInt(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
