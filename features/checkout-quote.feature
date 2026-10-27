@backend
Feature: Checkout quote and payment methods

  Scenario: Quote returns the bill
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    When I request a checkout quote for country "US"
    Then I get subtotal, shipping fee, tax and total, with total equal to their sum

  Scenario: Quote ignores client supplied prices
    When I request a quote claiming a unit price of 0.01
    Then the quote uses the database price

  Scenario: Empty cart is rejected
    Given my cart is empty
    When I request a checkout quote
    Then the response status is 400

  Scenario: Afterpay is offered inside limits and supported countries
    Given the total is within the Afterpay limits
    When I request payment methods for country "US"
    Then "CARD" and "AFTERPAY" are listed

  Scenario Outline: Afterpay is not offered
    When I request payment methods for country "<country>" with total <total>
    Then only "CARD" is listed
    Examples:
      | country | total   |
      | DE      | 50.00   |
      | US      | 0.50    |
      | US      | 99999.0 |
