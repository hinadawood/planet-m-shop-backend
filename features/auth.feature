@backend
Feature: Authentication and authorization

  Scenario: Register
    When I register with a valid email and password
    Then the response status is 201

  Scenario: Duplicate email
    Given an account exists for "a@example.com"
    When I register with "a@example.com"
    Then the response status is 409

  Scenario: Weak password
    When I register with a password that is too short
    Then the response status is 400

  Scenario: Login returns tokens
    When I log in with correct credentials
    Then I receive an access token valid for 15 minutes and a refresh token valid for 7 days

  Scenario: Wrong password
    When I log in with a wrong password
    Then the response status is 401 and failed_login_attempts increases

  Scenario: Lockout
    When I fail to log in repeatedly
    Then the account is locked until locked_until

  Scenario: Refresh rotates the token
    When I refresh with a valid refresh token
    Then I get a new pair and the old refresh token is rejected

  Scenario: Logout revokes the refresh token
    When I log out
    Then the refresh token can no longer be used

  Scenario: Expired access token
    When I call a protected endpoint with an expired token
    Then the response status is 401

  Scenario: Customers only see their own data
    When I request another customer's orders or addresses
    Then the response status is 403 or 404

  Scenario: Admin endpoints require the admin role
    When a customer calls POST /products
    Then the response status is 403
    When an admin calls POST /products
    Then the response status is 201

  Scenario: Passwords are hashed
    Then password_hash and token_hash never contain plain text
