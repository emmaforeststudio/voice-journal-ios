CREATE INDEX IF NOT EXISTS idx_email_verifications_requested_at
  ON email_verification_requests(requested_at);
