@backend
Feature: Customer and shipping address CRUD

  Scenario: Create, read, update and delete a customer
    When I create a customer then read, update and delete it
    Then each step returns the expected status (201, 200, 200, 204)

  Scenario: Duplicate email
    Given a customer with email "a@example.com" exists
    When I create another customer with that email
    Then the response status is 409

  Scenario: Shipping address CRUD for a customer
    Given a customer exists
    When I create, list, update and delete a shipping address
    Then each step succeeds and a missing address returns 404

  Scenario: Validation errors
    When I create a customer with an invalid email
    Then the response status is 400
