ALTER TABLE delivery_requests
  ADD COLUMN IF NOT EXISTS dropoff_address text NOT NULL DEFAULT '';
