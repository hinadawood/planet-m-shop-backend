# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status
Planet-M Shop backend: Spring Boot 3.5, Java 21, Maven, PostgreSQL 16, Redis 7, Cassandra 5, nginx gateway, Stripe, for a furniture-linens store. Only scaffolding exists (build config, DB schema/seed, ops SQL, Cassandra schema, nginx config, `OpenApiConfig`). The design is the approved plan in `docs/PLAN.md` (Revision 2) and is **not yet implemented**; update that file when design decisions change. The `features/*.feature` files are the requirements: work test-first (scenario → failing test → implementation). The frontend lives in a separate repo, `planet-m-shop-frontend` (Next.js BFF), which is the only client of this API.

## Toolchain
`.tool-versions` pins Temurin JDK 21 (asdf). If asdf isn't active in the shell, set `JAVA_HOME` to `~/.asdf/installs/java/temurin-21.0.13+9.0.LTS`.

## Commands
```bash
cp .env.example .env                  # then add Stripe test keys and a JWT secret (user supplies them)
docker compose up -d                  # postgres, redis, cassandra (+ schema init), nginx gateway (Docker Desktop must be running)
./mvnw spring-boot:run                # Spring listens on 8081; Flyway applies db/migrations on startup
./mvnw verify                         # all tests + JaCoCo report
./mvnw test -Dtest=ClassName#method   # single test
docker compose down                   # keeps data; add -v to wipe the pgdata and cassandradata volumes
```
Everything is reached through the nginx gateway on port 8080: Swagger UI at `http://localhost:8080/swagger-ui.html`, API at `http://localhost:8080/api/v1`. Spring's own port 8081 is not published by compose. For Stripe webhooks locally: `stripe listen --forward-to localhost:8080/webhooks/stripe` (Stripe CLI is not installed yet).

## Architecture (spans several files; read before changing)
**Data stores:** Postgres is the system of record for carts, orders, payments, inventory and customers. Redis holds only (1) idempotency keys, (2) the product/category read cache, (3) a cart cache (cache-aside; a Redis flush must lose nothing). Cassandra holds order history and the transaction log (`db/cassandra/schema.cql`), fed from a Postgres `outbox_events` table by a polling `OutboxPublisher` (`FOR UPDATE SKIP LOCKED`, no message broker; an `OrderEventSink` interface allows one later). Order status for the payment-success poll is read from Postgres, history from Cassandra.

**Database ownership:** Flyway (embedded, no container) is the only thing that creates/changes Postgres tables; Hibernate runs with `ddl-auto=validate`. `db/migrations/V*.sql` is what runs. `db/schema.sql` is a readable full DDL kept identical to `V1__baseline.sql` (a planned `SchemaSyncTest` compares them). Never edit a migration once any database has applied it; add a new `V<n>`. Docker Compose creates the empty `planetm` DB; it does not run `schema.sql`. Migrations in `db/migrations` run in every environment (V1 tables, V3 the restricted `planetm_app` role: Flyway connects as owner `planetm`, the app as `planetm_app`, which cannot DDL or UPDATE/DELETE the audit tables; new-table migrations must include GRANTs). Sample data lives in `db/seed-dev/` and loads only under the `dev` profile (the local default; production sets `SPRING_PROFILES_ACTIVE=prod`). The Cassandra schema is applied separately by the `cassandra-init` compose job. See `db/README.md`.

**Gateway:** browser → Next.js BFF → nginx (`nginx/nginx.conf`) → Spring. nginx rate-limits per real client IP (the BFF forwards the shopper's IP in `X-Forwarded-For`; nginx trusts it only from the addresses in `nginx/trusted-proxies.conf`: dev trusts just the compose gateway, production must list only the BFF's real address(es), never whole private ranges), blocks `/actuator`, passes `X-Request-Id`, and routes `/webhooks/stripe`. Swagger paths are open in the dev config only.

**Inventory:** available = `quantity_on_hand − quantity_reserved`. Add-to-cart only checks availability; the authoritative reservation happens at checkout via an atomic conditional `UPDATE ... WHERE on_hand - reserved >= :q` (plus `@Version`). A scheduled job expires unpaid orders (stock reserved 35 min, Stripe session 30 min). Availability is always read from Postgres, never Redis.

**Payments (Card or Afterpay via Stripe Checkout, hosted redirect):** Afterpay is a native Stripe method (`afterpay_clearpay`), so no extra library. The webhook, not the success redirect, is the source of truth. Each payment state change is ONE `@Transactional(rollbackFor = Exception.class)` method in its own bean (retry wrapper is a separate bean) containing: `INSERT ... ON CONFLICT DO NOTHING` into `processed_stripe_events`, `SELECT ... FOR UPDATE` on the order (lock order: orders → payments → inventory by product id), guarded `UPDATE ... WHERE status = ...` (continue only if 1 row changed), amount/currency check, stock change, `payment_events` and `outbox_events` rows. No Stripe call inside a transaction (create-session is two short transactions with the Stripe call between them). Webhook returns 2xx only after commit, 5xx on any error so Stripe retries. Redis eviction runs after commit. The full checklist (R1–R18, with code and tests) is in `docs/PLAN.md` — follow it.

**Idempotency:** `Idempotency-Key` header is required on place-order and create-checkout-session. Records live in Redis (`idem:{scope}:{key}`; 60 s in-progress marker, 24 h completed): same key + payload returns the stored result, different payload → 422, in progress → 409. Redis can't join the DB transaction, so the unique `idempotency_key` columns on `orders` and `payments` are the backstop (a replay finds the existing order). The key is also passed to Stripe. A partial unique index on `payments(order_id)` prevents two live payments per order.

**Auth:** customer accounts with JWT (Spring Security OAuth2 resource server, Nimbus, 15 min access / 7 day rotating refresh tokens stored hashed in `refresh_tokens`), roles CUSTOMER and ADMIN, BCrypt passwords, login lockout. The endpoint catalog with the auth level of each is in `docs/PLAN.md`.

**Conventions:** Lombok is available (avoid `@Data`/`@EqualsAndHashCode` on JPA entities). Every REST endpoint must be documented with springdoc annotations; a planned `OpenApiContractTest` keeps `docs/openapi.yaml` current — that file is the contract the frontend repo consumes. Categories are the generic set Bedroom, Dining, Living, Outdoor; specific items (sheets, cushion covers, sofa sets, runners) are products within them.
