CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('client', 'traveler', 'admin')),
  password_hash text NOT NULL,
  avatar_url text NOT NULL DEFAULT '',
  phone text NOT NULL DEFAULT '',
  bio text NOT NULL DEFAULT '',
  permanent_address text NOT NULL DEFAULT '',
  passport_number text NOT NULL DEFAULT '',
  country_of_residence text NOT NULL DEFAULT '',
  kyc_status text NOT NULL DEFAULT 'unverified',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS traveler_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  traveler_id uuid NOT NULL REFERENCES users(id),
  origin text NOT NULL,
  destination_type text NOT NULL CHECK (destination_type IN ('city', 'country')),
  destination text NOT NULL,
  departure_date timestamptz NOT NULL,
  arrival_date timestamptz NOT NULL,
  max_weight_kg double precision NOT NULL,
  price_per_kg double precision NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS delivery_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES users(id),
  origin text NOT NULL,
  destination_type text NOT NULL CHECK (destination_type IN ('city', 'country')),
  destination text NOT NULL,
  weight_kg double precision NOT NULL,
  package_description text NOT NULL DEFAULT '',
  declared_value double precision NOT NULL DEFAULT 0,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES traveler_listings(id),
  request_id uuid NOT NULL REFERENCES delivery_requests(id),
  agreed_price double precision NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS escrows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES matches(id),
  currency text NOT NULL,
  amount double precision NOT NULL,
  commission_amount double precision NOT NULL,
  traveler_amount double precision NOT NULL,
  status text NOT NULL,
  funded_at timestamptz NULL,
  released_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS kyc_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  document_type text NOT NULL,
  document_reference text NOT NULL,
  address_proof_ref text NOT NULL,
  status text NOT NULL,
  review_notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS package_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES delivery_requests(id),
  declared_contents text NOT NULL,
  receipt_ref text NOT NULL,
  screening_method text NOT NULL DEFAULT '',
  risk_score integer NOT NULL DEFAULT 0,
  status text NOT NULL,
  review_notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tracking_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES matches(id),
  status text NOT NULL,
  location text NOT NULL,
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS social_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_user_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_user_id)
);
