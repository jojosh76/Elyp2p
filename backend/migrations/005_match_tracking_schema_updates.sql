ALTER TABLE matches
  ADD COLUMN IF NOT EXISTS estimated_delivery_at timestamptz NULL;

ALTER TABLE tracking_events
  ADD COLUMN IF NOT EXISTS occurred_at timestamptz NULL;
