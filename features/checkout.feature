@backend
Feature: Checkout and order creation

  Scenario: Bill shows subtotal, shipping and tax
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    When I place the order with valid shipping details and payment method "CARD"
    Then the order total equals subtotal plus shipping fee plus tax

  Scenario: Creating the order reserves inventory
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    When I place the order with valid shipping details and payment method "CARD"
    Then the order status is "PENDING_PAYMENT"
    And 2 units of "LIV-CSH-45-OCH" are reserved

  Scenario Outline: Shipping details are validated
    When I place an order with <field> missing
    Then the response status is 400 and the error names "<field>"
    Examples:
      | field      |
      | fullName   |
      | line1      |
      | city       |
      | state      |
      | postalCode |
      | country    |
      | phone      |
      | email      |

  Scenario: Empty cart cannot be checked out
    Given my cart is empty
    When I place the order with valid shipping details and payment method "CARD"
    Then the response status is 400

  Scenario: Item became unavailable since it was added
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    And only 1 unit of "LIV-CSH-45-OCH" is now available
    When I place the order with valid shipping details and payment method "CARD"
    Then the response status is 409 with a clear message

  Scenario: Client supplied prices are ignored
    Given my cart contains 1 of "LIV-CSH-45-OCH"
    When I place the order and the request claims a unit price of 0.01
    Then the order total uses the database price

  Scenario: Guest checkout and returning email
    When I place an order as a guest with email "a@example.com"
    Then a guest customer is created
    When I place another order with email "a@example.com"
    Then the same customer is reused

  Scenario: Unsupported payment method
    When I place the order with payment method "BITCOIN"
    Then the response status is 400

  Scenario: Afterpay outside limits or unsupported country
    Given the order total is outside Afterpay limits
    When I place the order with payment method "AFTERPAY"
    Then the response status is 422
