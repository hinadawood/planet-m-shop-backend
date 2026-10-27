@backend
Feature: Database schema

  Scenario: schema.sql creates all tables
    When db/schema.sql is applied to an empty PostgreSQL database
    Then customers, shipping_addresses, categories, products, inventory, carts, cart_items, orders, order_items, payments, processed_stripe_events, idempotency_keys and inventory_movements exist

  Scenario: schema.sql matches the Flyway migrations
    Then the schema produced by db/migrations equals the schema produced by db/schema.sql

  Scenario: Flyway runs as the owner and the app runs as a restricted role
    Given Flyway has applied the migrations
    Then the role "planetm_app" exists and cannot create or drop tables

  Scenario: Audit tables are append-only for the app role
    When the application role updates, deletes or truncates payment_events, inventory_movements or processed_stripe_events
    Then each statement is rejected with permission denied
    And inserting into them, including INSERT ... ON CONFLICT DO NOTHING, succeeds

  Scenario: Lock and statement time limits are set for the app role
    Then lock_timeout is 5s, statement_timeout is 15s and idle_in_transaction_session_timeout is 30s for "planetm_app"

  Scenario: Sample data loads only in the dev profile
    When migrations run without the dev profile
    Then no categories or products exist
    When migrations run with the dev profile
    Then 4 categories, 5 products and 5 inventory rows exist
