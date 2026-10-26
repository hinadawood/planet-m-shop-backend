@backend
Feature: Product catalogue API
  Shoppers browse active products, optionally filtered by category or search text.

  Background:
    Given the categories "Bedroom", "Dining", "Living" and "Outdoor" exist
    And active products exist in several categories

  Scenario: List all active products
    When I request the product list
    Then the response status is 200
    And every product has a name, image url and price
    And inactive products are not returned

  Scenario: Filter products by category
    When I request products in category "living"
    Then only products in the "Living" category are returned, including cushion covers and sofa sets

  Scenario: Search products by name
    When I search products for "runner"
    Then only products whose name contains "runner" are returned

  Scenario: Paginate the product list
    Given there are more products than the page size
    When I request page 2 with size 2
    Then I receive the second page and the total element count

  Scenario: Product detail by id
    When I request product 1
    Then the response status is 200

  Scenario: Unknown product id
    When I request product 99999
    Then the response status is 404 with a problem detail body
