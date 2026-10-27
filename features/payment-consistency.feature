@backend
Feature: Payment consistency (ACID)
  Requirements R1-R18 in docs/PLAN.md. Tests run on a real Postgres via Testcontainers.

  Scenario Outline: Failure at any step rolls back every change
    Given a pending order with reserved stock
    And the <step> will fail
    When a valid "checkout.session.completed" webhook arrives
    Then the payment, order, inventory, audit rows and outbox are all unchanged
    And the processed event record does not exist
    Examples:
      | step                  |
      | payment update        |
      | order update          |
      | inventory update      |
      | audit write           |
      | outbox write          |

  Scenario: A checked exception also rolls back
    Given a pending order with reserved stock
    And the inventory step throws a checked exception
    When a valid "checkout.session.completed" webhook arrives
    Then nothing is committed

  Scenario: Two concurrent webhooks produce one effect
    Given a pending order with 2 reserved units
    When two identical webhooks are processed at the same time
    Then stock is deducted once and one payment_events row exists

  Scenario: Duplicate delivery after commit
    Given the event was already processed
    When it arrives again
    Then the response is 200 and nothing changes

  Scenario: Late failure after success is ignored
    Given the order is PAID
    When a "payment_intent.payment_failed" webhook arrives
    Then the order stays PAID

  Scenario: Expiry racing completion ends in one terminal state
    Given the expiry job and a completed webhook run at the same time
    Then exactly one terminal state results and stock is consistent

  Scenario: Amount mismatch is not marked paid
    Given Stripe reports a different amount than the order total
    When the webhook is processed
    Then the order is not PAID and a PAYMENT_MISMATCH event is recorded

  Scenario: Payment after the order expired
    Given the order is EXPIRED and its stock released
    When a completed webhook arrives
    Then a LATE_PAYMENT event is recorded and stock is re-reserved or the order is flagged for manual refund

  Scenario: Database failure returns 5xx so Stripe retries
    Given the database is failing
    When a valid webhook arrives
    Then the response is 5xx
    When Stripe retries after the database recovers
    Then the payment is applied

  Scenario: Invalid signature
    When a webhook has an invalid signature
    Then the response is 400 and nothing is written

  Scenario: Afterpay asynchronous failure releases stock
    Given an Afterpay payment is pending
    When "checkout.session.async_payment_failed" arrives
    Then the payment is FAILED, the order PAYMENT_FAILED and the reservation released

  Scenario: Stripe timeout leaves the order pending
    Given Stripe times out when creating the session
    Then the order stays PENDING_PAYMENT, stock stays reserved and the retry uses the same idempotency key

  Scenario: Reconciliation recovers a lost webhook
    Given Stripe shows a session as paid but no webhook arrived
    When the reconciliation job runs
    Then the order becomes PAID through the same transactional handler

  Scenario: Deadlock or version conflict is retried
    Given the first attempt fails with a deadlock
    Then the handler retries and the second attempt succeeds

  Scenario: No external call inside a transaction
    When a checkout session is created
    Then no Stripe call is made while a database transaction is active

  Scenario: Redis or Cassandra failure does not affect a committed payment
    Given Redis eviction and the Cassandra projector fail
    When a payment is committed
    Then the payment stays committed and the failures are logged
