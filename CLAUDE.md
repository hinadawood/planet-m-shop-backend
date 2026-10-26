# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status
Planet-M Shop backend: Spring Boot 3.5, Java 21, Maven, PostgreSQL 16, Redis 7, Stripe, for a furniture-linens store. Only scaffolding exists (build config, DB schema/seed, `OpenApiConfig`, ops SQL). The design below is the approved plan and is **not yet implemented**. The `features/*.feature` files are the requirements: work test-first (scenario → failing test → implementation). The full project plan (both repos, schema, API, Gherkin scenario list) is `docs/PLAN.md`; update it when design decisions change. The frontend lives in a separate repo, `planet-m-shop-frontend` (Next.js BFF), which is the only client of this API.

## Toolchain
`.tool-versions` pins Temurin JDK 21 (asdf). If asdf isn't active in the shell, set `JAVA_HOME` to `~/.asdf/installs/java/temurin-21.0.13+9.0.LTS`.

## Commands
```bash
cp .env.example .env                  # then add Stripe test keys (user supplies them)
docker compose up -d                  # Postgres + Redis only (Docker Desktop must be running)
./mvnw spring-boot:run                # Flyway applies db/migrations on startup
./mvnw verify                         # all tests + JaCoCo report
./mvnw test -Dtest=ClassName#method   # single test
docker compose down                   # keeps data; add -v to wipe the pgdata volume
```
Swagger UI: `http://localhost:8080/swagger-ui.html`. For Stripe webhooks locally: `stripe listen --forward-to localhost:8080/webhooks/stripe` (Stripe CLI is not installed yet).

## Architecture (spans several files; read before changing)
**Database ownership:** Flyway (embedded in the app, no container) is the only thing that creates/changes tables; Hibernate runs with `ddl-auto=validate`. `db/migrations/V*.sql` is what actually runs. `db/schema.sql` is a human-readable full DDL that must stay identical to the migrations (a planned `SchemaSyncTest` compares them). Never edit an already-applied migration; add a new `V<n>`. Docker Compose only creates the empty `planetm` DB; it does not run `schema.sql`. See `db/README.md`.

**Inventory:** available = `quantity_on_hand − quantity_reserved`. Add-to-cart only checks availability; the authoritative reservation happens at checkout via an atomic conditional `UPDATE ... WHERE on_hand - reserved >= :q` (plus `@Version`). A scheduled job expires unpaid orders (~30 min) and releases stock. Availability is always read from Postgres, never Redis.

**Payments (Card or Afterpay via Stripe Checkout, hosted redirect):** Afterpay is a native Stripe method (`afterpay_clearpay`), so no extra library. The webhook, not the success redirect, is the source of truth. The webhook handler is a single `@Transactional` method that inserts into `processed_stripe_events` (idempotency), updates `payments`, sets the order PAID, and converts reserved stock to sold; any failure rolls everything back so Stripe retries. Redis eviction happens in `afterCommit`. Stripe webhooks hit this service directly, not the frontend.

**Idempotency:** `Idempotency-Key` header is required on place-order and create-checkout-session. The `idempotency_keys` table stores request hash and response: same key + same payload returns the stored result, different payload → 422, concurrent duplicate → 409. The key is also passed to Stripe as its request idempotency key. A partial unique index on `payments(order_id)` prevents two live payments per order.

**Caching:** Redis via Spring Cache (`products`, `product`, `categories`, TTL ~10 min) with eviction on writes. A Redis outage must fall back to the database.

**Conventions:** Lombok is available (avoid `@Data`/`@EqualsAndHashCode` on JPA entities). Every REST endpoint must be documented with springdoc annotations; a planned `OpenApiContractTest` keeps `docs/openapi.yaml` current — that file is the contract the frontend repo consumes. Categories are the generic set Bedroom, Dining, Living, Outdoor; specific items (sheets, cushion covers, sofa sets, runners) are products within them.
