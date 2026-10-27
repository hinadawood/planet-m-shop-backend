@backend
Feature: Admin order and stock management

  Scenario: List and filter orders
    When an admin requests GET /admin/orders?status=PAID
    Then only PAID orders are returned, paged

  Scenario: Ship and deliver
    Given a PAID order
    When an admin sets the status to SHIPPED and then DELIVERED
    Then each change succeeds and an event is recorded

  Scenario: Illegal transitions are rejected
    Given a PENDING_PAYMENT order
    When an admin sets the status to SHIPPED
    Then the response status is 409

  Scenario: Customer cancels only while payment is pending
    Given a PENDING_PAYMENT order
    When the customer cancels it
    Then the order is CANCELLED and the stock is released
    Given a PAID order
    When the customer cancels it
    Then the response status is 409

  Scenario: Low stock listing
    When an admin requests GET /inventory?lowStock=true
    Then only products at or below their reorder level are returned
