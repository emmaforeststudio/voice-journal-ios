CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS email_verification_requests (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  email_hash TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  requested_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  consumed_at INTEGER,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_email_verifications_device_time
  ON email_verification_requests(device_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_verifications_lookup
  ON email_verification_requests(device_id, email_hash, requested_at DESC);

CREATE TABLE IF NOT EXISTS verified_emails (
  device_id TEXT NOT NULL,
  email_hash TEXT NOT NULL,
  encrypted_email TEXT NOT NULL,
  verified_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, email_hash),
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS future_email_letters (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  encrypted_payload TEXT NOT NULL,
  delivery_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL,
  provider_id TEXT,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  delivered_at INTEGER,
  canceled_at INTEGER,
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_future_email_letters_due
  ON future_email_letters(status, next_attempt_at, delivery_at);

CREATE INDEX IF NOT EXISTS idx_future_email_letters_device
  ON future_email_letters(device_id, created_at DESC);
