@backend
Feature: Swagger / OpenAPI documentation

  Scenario: Every endpoint is documented
    When I fetch /v3/api-docs
    Then every controller endpoint appears with a summary and its response codes

  Scenario: Idempotency-Key is documented
    Then the order checkout and payment endpoints list Idempotency-Key as a required header

  Scenario: Exported spec is current
    Then docs/openapi.yaml matches the generated specification
