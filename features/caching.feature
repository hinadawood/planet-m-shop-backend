@backend
Feature: Redis caching

  Scenario: Second read is served from cache
    When I read the product list twice
    Then the repository is called once

  Scenario: Writes evict cache entries
    Given the product list is cached
    When a product is updated or deleted
    Then the product cache entries are evicted

  Scenario: Redis outage falls back to the database
    Given Redis is unavailable
    When I read the product list
    Then the data comes from the database and the response is 200
