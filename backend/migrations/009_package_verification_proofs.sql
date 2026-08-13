-- Add challenge token and QR to delivery requests; add proof fields to package verifications
ALTER TABLE delivery_requests
    ADD COLUMN IF NOT EXISTS challenge_token text,
    ADD COLUMN IF NOT EXISTS qrcode_data text;

ALTER TABLE package_verifications
    ADD COLUMN IF NOT EXISTS challenge_token text,
    ADD COLUMN IF NOT EXISTS photo_hashes jsonb,
    ADD COLUMN IF NOT EXISTS proof_gps text,
    ADD COLUMN IF NOT EXISTS proof_weight_kg numeric;

-- Backfill empty json arrays for existing rows (optional)
UPDATE package_verifications SET photo_hashes = '[]'::jsonb WHERE photo_hashes IS NULL;
