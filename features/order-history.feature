@backend
Feature: Order history in Cassandra
  Postgres is the system of record; history is projected to Cassandra after the outbox publishes.

  Scenario: Paid order appears in the customer's history
    Given a customer paid for an order
    When the outbox publisher runs
    Then GET /orders returns the order from Cassandra

  Scenario: History is newest first
    Given a customer has three orders placed on different days
    When I request my order history
    Then the orders are returned newest first

  Scenario: Transaction log is returned in order
    Given an order went from placed to paid to shipped
    When I request GET /orders/{publicId}/events
    Then the events are returned oldest first with their types

  Scenario: Customer cannot read another customer's history
    When I request another customer's order events
    Then the response status is 403 or 404

  Scenario: Cassandra down falls back to Postgres
    Given Cassandra is unavailable
    When I request my order history
    Then the list is served from Postgres with status 200

  Scenario: No orders
    When a customer with no orders requests history
    Then an empty list is returned

  Scenario: Current order status stays on Postgres
    Given an order was just paid and not yet published
    When I request GET /orders/{publicId}
    Then the status is PAID
