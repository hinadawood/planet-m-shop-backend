@backend
Feature: Product and category admin CRUD

  Scenario: Create, update and soft-delete a product
    When an admin creates, updates and deletes a product
    Then statuses are 201, 200 and 204 and the product becomes inactive

  Scenario: Duplicate SKU
    Given a product with SKU "BED-SHT-QN-WHT" exists
    When an admin creates another product with that SKU
    Then the response status is 409

  Scenario: Category CRUD
    When an admin creates, reads, updates and deletes a category
    Then each step succeeds and unknown ids return 404

  Scenario: Non-admin cannot write
    When an anonymous user creates a product
    Then the response status is 401 or 403
