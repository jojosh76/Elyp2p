ALTER TABLE delivery_requests
  ADD COLUMN IF NOT EXISTS recipient_name text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS recipient_phone text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS recipient_photo_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS dropoff_instructions text NOT NULL DEFAULT '';

ALTER TABLE escrows
  ADD COLUMN IF NOT EXISTS payout_status text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payout_provider text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payout_reference text NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL DEFAULT '',
  payload text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE(provider, provider_event_id)
);
