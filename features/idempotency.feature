@backend
Feature: Idempotent Place order and payment API

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

  Scenario: Concurrent duplicates
    When two requests with key "k2" arrive at the same time
    Then one proceeds and the other receives 409

  Scenario: Key is forwarded to Stripe
    When I create a checkout session with key "k3"
    Then Stripe receives the request Idempotency-Key "k3"

  Scenario: Failed first attempt leaves no completed record
    Given the first attempt with key "k4" failed for out of stock
    When I retry with key "k4" after restocking
    Then the order is created
