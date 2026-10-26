DELETE FROM idempotency_keys WHERE expires_at < now();
