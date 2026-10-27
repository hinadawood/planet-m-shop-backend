@backend
Feature: nginx gateway and rate limiting
  Verified by a compose smoke script, not by unit tests.

  Scenario: Spring is not reachable directly
    Then port 8081 is not published and only nginx on port 8080 is

  Scenario: Requests are routed to the API
    When I call GET /api/v1/products through the gateway
    Then I get the product list

  Scenario: Internal endpoints are blocked
    When I call /actuator/health through the gateway
    Then the response status is 404

  Scenario: Over the limit returns 429
    When one client sends 50 checkout requests within a second
    Then later requests receive 429 with a Retry-After header

  Scenario: Limits apply per forwarded client IP
    Given two shoppers reach the gateway through the same BFF
    When the first exceeds the limit
    Then the second is not limited

  Scenario: Login attempts are limited more strictly
    When one client sends 20 login requests within a minute
    Then requests beyond the limit receive 429

  Scenario: Request id is passed through
    When a request carries X-Request-Id "abc"
    Then the backend receives "abc" and the response returns it
    And a request without the header gets a generated id

  Scenario: Stripe webhook is routed with its own limit
    When Stripe posts to /webhooks/stripe through the gateway
    Then the request reaches Spring and is not throttled by the shopper limits
