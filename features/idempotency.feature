@backend
Feature: Idempotent Place order and payment API
  Idempotency records live in Redis; unique idempotency_key columns on orders and payments in Postgres are the backstop.

  Scenario: Missing Idempotency-Key
    When I place an order without an Idempotency-Key header
    Then the response status is 400

  Scenario: Same key and payload returns the original result
    Given I placed an order with key "k1"
    When I repeat the same request with key "k1"
    Then I get the original order and Stripe url
    And no second order, reservation or Stripe session is created

  Scenario: Same key with different payload
    Given I placed an order with key "k1"
    When I send a different payload with key "k1"
    Then the response status is 422

  Scenario: In-progress marker blocks a concurrent duplicate
    Given a request with key "k2" is in progress
    When a second request with key "k2" arrives
    Then the response status is 409

  Scenario: Concurrent duplicates
    When two requests with key "k2" arrive at the same time
    Then one proceeds and the other receives 409

  Scenario: Redis record is stored with the right lifetimes
    When an order is placed with key "k5"
    Then the Redis record is in progress for at most 60 seconds and completed for 24 hours

  Scenario: Redis was flushed
    Given I placed an order with key "k6"
    And the Redis idempotency record is gone
    When I repeat the same request with key "k6"
    Then the original order is returned from the unique idempotency_key in Postgres
    And no second order is created

  Scenario: Redis is down
    Given Redis is unavailable
    When I repeat a request with an existing key
    Then no duplicate order or payment is created

  Scenario: Key is forwarded to Stripe
    When I create a checkout session with key "k3"
    Then Stripe receives the request Idempotency-Key "k3"

  Scenario: Failed first attempt leaves no completed record
    Given the first attempt with key "k4" failed for out of stock
    When I retry with key "k4" after restocking
    Then the order is created
