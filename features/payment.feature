@backend
Feature: Stripe payments, webhooks and transactional status updates

  Scenario: Create a Stripe Checkout Session with amount and currency
    Given a pending order with total 59.98 USD
    When I create a checkout session
    Then Stripe is called with amount 5998 and currency "usd"

  Scenario Outline: Payment method maps to Stripe payment method types
    Given a pending order
    When I create a checkout session with payment method "<method>"
    Then Stripe is called with payment_method_types "<stripeType>"
    Examples:
      | method   | stripeType       |
      | CARD     | card             |
      | AFTERPAY | afterpay_clearpay|

  Scenario: Webhook success updates payment, order and stock in one transaction
    Given a pending order with reserved stock
    When a valid "checkout.session.completed" webhook arrives
    Then the payment is "SUCCEEDED" and the order is "PAID"
    And stock is committed and inventory movements are recorded
    And all of these changes are in a single transaction

  Scenario: Any failure rolls back the whole update
    Given a pending order with reserved stock
    And updating the inventory will fail
    When a valid "checkout.session.completed" webhook arrives
    Then the payment, order and inventory are unchanged

  Scenario: Duplicate webhook delivery is processed once
    Given a webhook event was already processed
    When the same event arrives again
    Then nothing changes and the response is 200

  Scenario: Invalid signature
    When a webhook arrives with an invalid signature
    Then the response status is 400 and nothing changes

  Scenario: Payment failure releases the reservation
    Given a pending order with reserved stock
    When a "payment_intent.payment_failed" webhook arrives
    Then the payment is "FAILED", the order is "PAYMENT_FAILED" and the reservation is released

  Scenario: Abandoned checkout expires
    Given a pending order older than the reservation timeout
    When the expiry job runs
    Then the order is "EXPIRED" and the stock is released
