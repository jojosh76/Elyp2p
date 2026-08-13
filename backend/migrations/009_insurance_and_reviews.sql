ALTER TABLE escrows
  ADD COLUMN IF NOT EXISTS insurance_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS coverage_limit double precision NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS insurance_premium double precision NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS insurance_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  escrow_id uuid NOT NULL REFERENCES escrows(id),
  claimant_id uuid NOT NULL REFERENCES users(id),
  reason text NOT NULL,
  requested_amount double precision NOT NULL,
  status text NOT NULL DEFAULT 'pending_review',
  review_notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES matches(id),
  author_id uuid NOT NULL REFERENCES users(id),
  target_id uuid NOT NULL REFERENCES users(id),
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (match_id, author_id)
);
