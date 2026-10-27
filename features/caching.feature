@backend
Feature: Redis caching
  Redis is used for idempotency keys, the product/category read cache and the cart cache only.

  Scenario: Second read is served from cache
    When I read the product list twice
    Then the repository is called once

  Scenario: Writes evict cache entries
    Given the product list is cached
    When a product is updated or deleted
    Then the product cache entries are evicted

  Scenario: Stock is never served from the cache
    Given a product is cached
    When its available stock changes
    Then the availability endpoint returns the value from Postgres

  Scenario: Redis outage falls back to the database for products and carts
    Given Redis is unavailable
    When I read the product list and my cart
    Then the data comes from Postgres and the responses are 200

  Scenario: Orders and payments are never stored in Redis
    When an order is placed and paid
    Then no order or payment data exists in Redis other than the idempotency record
