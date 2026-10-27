@backend
Feature: Cart with inventory checks
  The cart is stored in Postgres; Redis is a cache-aside copy.

  Background:
    Given product "LIV-CSH-45-OCH" has 5 units available

  Scenario: Add an in-stock product to an empty cart
    When I add 2 of "LIV-CSH-45-OCH" to my cart
    Then the cart contains 2 of "LIV-CSH-45-OCH"
    And the cart total equals 2 times the unit price

  Scenario: Adding the same product again increases the quantity
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    When I add 1 of "LIV-CSH-45-OCH" to my cart
    Then the cart contains 3 of "LIV-CSH-45-OCH"

  Scenario: Reject quantity above available stock
    When I add 6 of "LIV-CSH-45-OCH" to my cart
    Then the response status is 409
    And the message says "Only 5 left"

  Scenario: Reject an out-of-stock product
    Given product "OUT-CSH-50-TEAL" has 0 units available
    When I add 1 of "OUT-CSH-50-TEAL" to my cart
    Then the response status is 409

  Scenario Outline: Reject invalid quantities
    When I add <qty> of "LIV-CSH-45-OCH" to my cart
    Then the response status is 400
    Examples:
      | qty |
      | 0   |
      | -1  |

  Scenario: Update, remove and clear
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    When I update "LIV-CSH-45-OCH" to quantity 4
    Then the cart contains 4 of "LIV-CSH-45-OCH"
    When I remove "LIV-CSH-45-OCH"
    Then the cart is empty
    When I clear the cart
    Then the cart is empty

  Scenario: Cart totals recalculate after every change
    When I add 1 of "LIV-CSH-45-OCH" to my cart
    And I add 1 of "DIN-RUN-180-NVY" to my cart
    Then the cart total is the sum of the line totals

  Scenario: Cart is saved in Postgres
    When I add 2 of "LIV-CSH-45-OCH" to my cart
    Then the carts and cart_items tables contain the cart

  Scenario: Cart survives a Redis flush
    Given my cart contains 2 of "LIV-CSH-45-OCH"
    And Redis is flushed
    When I read my cart
    Then the cart still contains 2 of "LIV-CSH-45-OCH"
    And the cart cache is repopulated

  Scenario: Cart cache is refreshed on every change and evicted on checkout
    Given my cart is cached
    When I change the cart
    Then the cache holds the new contents
    When I check out
    Then the cart cache entry is evicted

  Scenario: Guest cart merges into the account cart on login
    Given a guest cart with 2 of "LIV-CSH-45-OCH" and an account cart with 2 of "LIV-CSH-45-OCH"
    When the customer logs in and the carts are merged
    Then the quantity is 4 capped at the available stock
