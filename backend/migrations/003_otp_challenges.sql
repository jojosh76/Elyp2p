CREATE TABLE IF NOT EXISTS otp_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone text NOT NULL,
  purpose text NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  verified_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT NOW()
);
