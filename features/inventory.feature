@backend
Feature: Inventory

  Scenario: Available equals on-hand minus reserved
    Given a product with 10 on hand and 3 reserved
    Then 7 units are available

  Scenario: Last unit is reserved only once under concurrency
    Given a product with 1 unit available
    When two customers reserve it at the same time
    Then exactly one reservation succeeds

  Scenario: Release restores availability and stock never goes negative
    Given 2 units are reserved
    When the reservation is released
    Then availability increases by 2
    And releasing more than reserved is rejected

  Scenario: Admin sets stock and the product cache is evicted
    When an admin sets stock for a product to 50
    Then available stock is 50 and the cached product is evicted
