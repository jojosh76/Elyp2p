ALTER TABLE users
  ADD COLUMN IF NOT EXISTS payout_provider text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payout_account_id text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payout_account_status text NOT NULL DEFAULT '';
