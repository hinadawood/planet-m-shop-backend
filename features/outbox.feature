@backend
Feature: Transactional outbox

  Scenario: Outbox row is written in the same transaction as the payment update
    When a payment succeeds
    Then the payment, order, stock change and outbox row are committed together

  Scenario: Outbox row is rolled back with the payment update
    Given updating the inventory will fail
    When a payment webhook is processed
    Then no outbox row exists

  Scenario: Publisher marks rows published
    Given unpublished outbox rows exist
    When the OutboxPublisher runs
    Then the events are written to Cassandra and published_at is set

  Scenario: Duplicate delivery is harmless
    Given an event was written to Cassandra but not marked published
    When the publisher runs again
    Then the Cassandra rows are unchanged

  Scenario: Failed publish retries
    Given Cassandra rejects the first write
    When the publisher runs twice
    Then attempts is incremented and the second run publishes the event

  Scenario: Two publishers never take the same row
    Given 100 unpublished rows and two publishers running at the same time
    Then every row is published exactly once

  Scenario: Old published rows are purged
    Given rows published more than 7 days ago
    When the maintenance script runs
    Then they are deleted
