@backend
Feature: Database schema

  Scenario: schema.sql creates all tables
    When db/schema.sql is applied to an empty PostgreSQL database
    Then customers, shipping_addresses, categories, products, inventory, carts, cart_items, orders, order_items, payments, processed_stripe_events, idempotency_keys and inventory_movements exist

  Scenario: schema.sql matches the Flyway migrations
    Then the schema produced by db/migrations equals the schema produced by db/schema.sql
