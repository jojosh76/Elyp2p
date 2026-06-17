CREATE TABLE IF NOT EXISTS oauth_provider_configs (
  provider text PRIMARY KEY CHECK (provider IN ('google', 'apple')),
  enabled boolean NOT NULL DEFAULT true,
  client_id text NOT NULL DEFAULT '',
  ios_client_id text NOT NULL DEFAULT '',
  web_client_id text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

INSERT INTO oauth_provider_configs (provider, enabled)
VALUES ('google', true)
ON CONFLICT (provider) DO NOTHING;

INSERT INTO oauth_provider_configs (provider, enabled)
VALUES ('apple', true)
ON CONFLICT (provider) DO NOTHING;
