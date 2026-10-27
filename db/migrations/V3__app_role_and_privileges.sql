-- Privileges only (no tables). Runs as the owner role (planetm) via Flyway.
-- Rule: any later migration that adds a table must include its own GRANT lines for planetm_app.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'planetm_app') THEN
    CREATE ROLE planetm_app LOGIN PASSWORD '${app_db_password}';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE planetm TO planetm_app;
GRANT USAGE ON SCHEMA public TO planetm_app;
REVOKE CREATE ON SCHEMA public FROM planetm_app;

-- Mutable tables
GRANT SELECT, INSERT, UPDATE, DELETE ON
    customers, refresh_tokens, shipping_addresses, categories, products, inventory,
    carts, cart_items, orders, order_items, payments
TO planetm_app;

-- Append-only audit tables: no UPDATE / DELETE / TRUNCATE for the app role
GRANT SELECT, INSERT ON payment_events, inventory_movements, processed_stripe_events TO planetm_app;

-- Outbox: publisher sets published_at; purging old rows is an ops script run by the owner role
GRANT SELECT, INSERT, UPDATE ON outbox_events TO planetm_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO planetm_app;

-- Time limits so nothing hangs while holding locks (R13)
ALTER ROLE planetm_app SET lock_timeout = '5s';
ALTER ROLE planetm_app SET statement_timeout = '15s';
ALTER ROLE planetm_app SET idle_in_transaction_session_timeout = '30s';
