# Planet-M Shop — Project Plan

## Revision history
| Rev | Date | Summary |
|---|---|---|
| 1 | 2026-10-26 | Initial plan: two repos (Spring Boot backend, Next.js UI + BFF), Postgres schema, Swagger-documented REST API, Redis cache, Stripe Card/Afterpay payments, idempotency, Gherkin-first tests. |
| 2 | 2026-10-28 | Redis limited to idempotency keys + product cache + cart cache; Postgres is the source of truth for carts, orders and payments. Cassandra order history/transaction log via a transactional outbox (no message broker). nginx gateway with per-client-IP rate limiting. ACID compliance checklist (R1–R18). Customer accounts with JWT and an admin role. Complete API catalog (quote, payment methods, history, admin). |
| 2.1 | 2026-10-28 | Scaffold review fixes: stale purge script replaced by `purge_published_outbox.sql`; `planetm_app` role and privileges (V3); sample data moved to a dev-only Flyway location (`db/seed-dev`, dev profile is the local default); Cassandra schema documented in `db/README.md`; nginx real-IP trust narrowed to explicit proxy addresses. Verified on scratch databases and a live nginx test (see the review notes in the conversation).

## Context
Planet-M Shop is a greenfield e-commerce site for a furniture-linens company (bed sheets, cushion covers, sofa sets, dining runners, etc.). This plan defines everything from scratch: repo layout, stack, database schema, REST API, caching, payment flow, and a **Gherkin-first (TDD) test suite that acts as the requirements**. Implementation follows the Gherkin scenarios: write feature file → write failing unit tests → implement → green.

Scope (v1): (1) product catalogue with category pills, (2) add-to-cart with inventory checks, (3) checkout with bill quote + shipping form + payment-method choice (Card or Afterpay), (4) payment via redirect to Stripe, with payment status persisted transactionally, (5) customer accounts (JWT) with order history, (6) admin API for products, stock and orders. Basic CRUD API for all core entities.

## Tech stack
| Layer | Choice |
|---|---|
| Frontend + BFF | Next.js (App Router, `/app` directory) + React + TypeScript, Redux Toolkit (+ RTK Query), Tailwind CSS, `@stripe/stripe-js`. Routing is Next's file-system router (no React Router). Product pages are server-side rendered (React Server Components). The BFF layer is Next Route Handlers under `app/api/**` |
| Gateway | nginx in front of Spring Boot: single entry point, hides the backend host, per-client-IP rate limiting (`limit_req`), blocks internal endpoints |
| Backend | Java 21, Spring Boot 3.x, Maven, Spring Web, Spring Data JPA (Hibernate), Bean Validation, Lombok, Spring Security (OAuth2 resource server / JWT), springdoc-openapi, Spring Retry, MapStruct |
| DB (system of record) | PostgreSQL 16, migrations via Flyway: carts, orders, payments, inventory, customers |
| Order history | Cassandra 5 (`spring-boot-starter-data-cassandra`): order history and transaction log, fed from a Postgres transactional outbox |
| Cache / idempotency | Redis 7: (1) idempotency keys, (2) product/category read cache via Spring Cache, (3) cart cache (cache-aside). Nothing else |
| Payments | Stripe Checkout (hosted page), Card or Afterpay. Backend creates a Checkout Session; frontend redirects to it; Stripe webhook confirms payment |
| Frontend tests | Jest via `next/jest`, React Testing Library, `@testing-library/user-event`, MSW (API mocking), `jest-cucumber` (runs Gherkin); BFF route handlers tested in Jest `node` environment |
| Backend tests | JUnit 5, Mockito, AssertJ, `@WebMvcTest` + MockMvc, `@DataJpaTest`, Testcontainers (Postgres, Redis, Cassandra), Cucumber-JVM, JaCoCo, WireMock/Stripe mocks |
| Local infra | Docker Compose (postgres, redis, cassandra, nginx; backend and frontend optional) |

## Environment prerequisites (macOS, Apple Silicon — checked on this machine)
Persistence stays as planned: Spring Data JPA on Hibernate (implicit via `spring-boot-starter-data-jpa`), no change.

| Tool | Needed | Found on machine | Action | Who |
|---|---|---|---|---|
| JDK | 21 LTS (decided; project pinned via `<java.version>21</java.version>`). LTS = Long-Term Support: years of security patches; installed 23 is non-LTS and no longer patched | OpenJDK 23.0.2 (stays installed, untouched) | `brew install --cask temurin@21` (or asdf), then select 21 for this project via `JAVA_HOME` | Claude (non-risky) or you |
| Maven | 3.9+ | 3.9.9 | None (or use the `./mvnw` wrapper) | — |
| Node.js | 20.9+ (22 LTS recommended) for Next.js | 21.5.0 via asdf (too old / non-LTS; warns about `NODE_OPTIONS=--use-system-ca`) | `asdf install nodejs 22.x` then `asdf set nodejs 22.x` (21.5.0 stays installed) | Claude (non-risky) or you |
| npm | 10+ | 10.2.4 | None (ships with Node 22) | — |
| Docker Desktop + Compose v2 | Postgres 16, Redis 7, Testcontainers | CLI 27.3.1, Compose v2.30.3 installed, **daemon not running** | Launch Docker Desktop | You |
| PostgreSQL / Redis / Cassandra / nginx | via Docker Compose containers | Not installed locally | Nothing to install locally (Cassandra needs roughly 1 GB of Docker Desktop memory; heap is capped in compose) | — |
| Stripe CLI | Forward test webhooks (`stripe listen --forward-to localhost:8080/webhooks/stripe`) | Missing | `brew install stripe/stripe-cli/stripe`, then `stripe login` | Claude installs; you run `stripe login` (browser auth) |
| Stripe account + test keys | Publishable key, secret key, webhook signing secret | — | Create account at stripe.com, copy **test-mode** keys into `.env` files (never committed) | You |
| Git, Homebrew, gh, curl | VCS and tooling | All present | None | — |

**What Claude can do (non-risky, only after plan approval):** install Node 22 via asdf, JDK 21 (optional), Stripe CLI via Homebrew; run version checks; scaffold the project, generate `.env.example` files, and run builds/tests. All installs are user-level and reversible.
**What you do yourself:** start Docker Desktop; create the Stripe account and paste test keys into local `.env` files; `stripe login`; any system-level/admin installs. Claude never enters credentials or keys.
**Automatic via the project:** all Maven and npm dependencies (Spring Boot, Hibernate, Flyway, Mockito, Cucumber, Next.js, Tailwind, Redux Toolkit, Jest, RTL, etc.) and the Postgres/Redis containers via `docker compose up`.

## Repository layout — two repositories
**`planet-m-shop-backend`** (Spring Boot API + database scripts) and **`planet-m-shop-frontend`** (Next.js UI + BFF). Independent repos, independent CI and release cycles; they integrate only through the REST contract (the OpenAPI spec the backend publishes) and shared env var names.

**Do we need a third repo for SQL scripts (including frequently-run procedures and backup scripts)? No — still not required.** Scripts are backed up by git itself: the backend repo's remote (GitHub) is the backup, with history and review. Operational SQL that is run repeatedly lives in a `db/ops/` folder of the backend repo (see tree): `procedures/` (stored procedures/functions, applied through Flyway repeatable `R__*.sql` migrations so they are versioned and re-applied when changed), `maintenance/` (purge published outbox rows, expire unpaid orders, low-stock report, reconcile reserved vs. open orders) and `backup/` (`pg_dump` / restore shell scripts). Business logic stays in Java services and scheduled jobs rather than stored procedures; use procedures only for set-based maintenance. Note the *data* backups (dump files) are not stored in git; they go to object storage / managed-Postgres snapshots. The backend is the only service that owns and writes to the database, so the schema must version, review and deploy together with the entity/Flyway code that depends on it; a separate SQL repo would add sync overhead and the risk of schema/code drift. A third repo is only worthwhile if several services share one database or a separate DBA/ops team owns schema releases and backups with its own access controls — neither applies today; revisit if that changes. SQL therefore lives in `planet-m-shop-backend/db/`. (Can be split out later with `git subtree split` if needed.)

### Repo 1 — `planet-m-shop-backend`
```
planet-m-shop-backend/
├── README.md
├── docker-compose.yml            # postgres:16 (plain image; Flyway embedded in the backend creates the schema on startup), redis:7, cassandra:5 (+ init job applying db/cassandra/schema.cql), nginx gateway. Spring Boot is NOT published; only nginx (port 8080) is
├── .env.example                  # DB_URL, REDIS_HOST, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
├── features/                     # Gherkin requirements tagged @backend (source of truth for backend tests)
│   ├── catalogue, cart, checkout, checkout-quote, payment, payment-consistency, idempotency
│   ├── inventory, customer, product-admin, admin-orders, auth, order-history, outbox
│   ├── caching, gateway, swagger, schema   (each a .feature file)
├── db/
│   ├── schema.sql                # full DDL for ALL tables, constraints and indexes (canonical, readable reference)
│   ├── cassandra/schema.cql      # keyspace planetm: orders_by_customer, order_by_id, order_events_by_order
│   ├── seed.sql                  # categories (Bedroom, Dining, Living, Outdoor) + sample products/inventory (same content as seed-dev/V2__seed.sql)
│   ├── seed-dev/V2__seed.sql     # sample data, loaded by Flyway ONLY in the dev profile (production starts empty)
│   ├── ops/                      # frequently-run SQL: procedures/ (R__*.sql repeatable), maintenance/, backup/ (pg_dump/restore scripts + README)
│   └── migrations/               # Flyway, every environment: V1__baseline.sql (= schema.sql), V3__app_role_and_privileges.sql (restricted planetm_app role), later incremental changes
├── nginx/nginx.conf              # gateway: routing, rate-limit zones, blocked paths, real-IP handling
├── docs/
│   ├── architecture.md           # diagrams, payment sequence
│   └── openapi.yaml              # exported Swagger/OpenAPI spec, committed; contract for the frontend repo
├── pom.xml
└── src/
│       ├── main/java/com/planetm/shop/
│       │   ├── PlanetMShopApplication.java
│       │   ├── config/           # RedisConfig, CacheConfig, StripeConfig, SecurityConfig, OpenApiConfig
│       │   ├── common/           # ApiError, GlobalExceptionHandler, exceptions (NotFound, OutOfStock, ...)
│       │   ├── product/          # Product, Category, ProductController, ProductService, ProductRepository, dto/
│       │   ├── inventory/        # Inventory, InventoryService, InventoryRepository
│       │   ├── customer/         # Customer, ShippingAddress, controllers/services/repos
│       │   ├── cart/             # Cart, CartItem, CartService (Redis-backed), CartController
│       │   ├── order/            # Order, OrderItem, OrderService, OrderController
│       │   └── payment/          # Payment, StripeGateway, PaymentService, StripeWebhookController, ProcessedStripeEvent
│       ├── main/resources/
│       │   └── application.yml (+ -dev, -test)   # flyway.locations=filesystem:db/migrations; springdoc paths
│       └── test/
│           ├── java/.../         # unit (Mockito), web slice, repo slice, integration, OpenApiContractTest, SchemaSyncTest
│           └── resources/        # Cucumber config pointing at ../../../features
```
`SchemaSyncTest` (Testcontainers) applies `db/migrations` to one Postgres and `db/schema.sql` to another and fails if the resulting schemas differ, so `schema.sql` can never drift from the migrations.

### Repo 2 — `planet-m-shop-frontend`
```
planet-m-shop-frontend/
├── README.md
├── docker-compose.yml            # optional: runs the frontend against a backend started from the backend repo
├── features/                     # Gherkin requirements tagged @frontend (bff-ssr, catalogue, cart, checkout, payment)
├── docs/openapi.yaml             # copy of the backend contract (used by MSW handlers / typed client generation)
├── package.json, next.config.mjs, tailwind.config.ts, postcss.config.js, jest.config.ts, tsconfig.json
    ├── .env.local.example        # BACKEND_URL, STRIPE_PUBLISHABLE_KEY (server-only secrets never exposed to browser)
    ├── app/                      # ROUTING + BFF (file-system router replaces react-router)
    │   ├── layout.tsx            # root layout, <StoreProvider>, Header/Footer
    │   ├── globals.css           # @tailwind directives
    │   ├── page.tsx              # Home -> SSR catalogue (server component)
    │   ├── products/
    │   │   ├── page.tsx          # SSR product list (searchParams: category, q, page)
    │   │   ├── loading.tsx, error.tsx
    │   │   └── [id]/page.tsx     # SSR product detail + generateMetadata (SEO); notFound() on 404
    │   ├── cart/page.tsx         # client page (Redux cart)
    │   ├── login/page.tsx, register/page.tsx
    │   ├── account/page.tsx, account/orders/page.tsx, account/orders/[id]/page.tsx   # protected; redirect to /login
    │   ├── checkout/page.tsx     # bill + shipping form + payment-method form (client)
    │   ├── payment/
    │   │   ├── success/page.tsx
    │   │   └── cancel/page.tsx
    │   └── api/                  # BFF route handlers (browser talks ONLY to these)
    │       ├── auth/{register,login,logout,session}/route.ts, account/{profile,addresses,password}/route.ts
    │       ├── categories/route.ts, products/route.ts, products/[id]/route.ts
    │       ├── checkout/quote/route.ts, payment-methods/route.ts
    │       ├── cart/route.ts, cart/items/route.ts, cart/items/[productId]/route.ts
    │       ├── orders/checkout/route.ts, orders/route.ts, orders/[id]/route.ts, orders/[id]/events/route.ts, orders/[id]/cancel/route.ts
    │       └── payments/checkout-session/route.ts
    ├── src/
    │   ├── bff/                  # server-only: backendClient.ts (fetch to Spring API, session cookie/token handling, error mapping), mappers (backend DTO -> UI view model)
    │   ├── store/                # makeStore.ts, StoreProvider.tsx (per-request store), hooks.ts
    │   ├── services/             # RTK Query slices hitting /api/* BFF: productsApi, cartApi, ordersApi, paymentsApi
    │   ├── features/
    │   │   ├── catalogue/        # catalogueSlice (filters), ProductGrid, ProductCard, CategoryPills  (grid/card are server components; pills + add-to-cart button are client)
    │   │   ├── cart/             # cartSlice, CartItemRow, CartSummary, CartBadge
    │   │   ├── checkout/         # checkoutSlice (incl. paymentMethod + idempotencyKey), ShippingForm, PaymentMethodForm, OrderSummary
    │   │   └── payment/          # PaymentRedirect (client, loadStripe), OrderStatusPoller
    │   ├── components/           # Header, Footer, Spinner, ErrorBanner, QuantityStepper
    │   └── test/                 # setupTests.ts, msw handlers, test-utils (renderWithProviders)
    └── __tests__/                # component, slice, page and route-handler tests + jest-cucumber step files
```

**Rendering split:** Product list/detail are async server components that call the BFF's `backendClient` directly on the server (no browser round trip), using `fetch(..., { next: { revalidate: 60, tags: ['products'] } })`; the BFF `revalidateTag('products')` after product/inventory changes. Interactive pieces (add-to-cart, cart, checkout form, payment redirect) are client components using Redux. The Redux store is created per request in `StoreProvider`; SSR-fetched products are passed as props / preloaded into state for hydration. Live stock is re-checked on add-to-cart through the BFF (SSR output may be up to 60s stale).

**BFF responsibilities:** hides the Spring base URL and Stripe keys from the browser; manages the guest cart session token in an `httpOnly` cookie; aggregates calls (e.g. checkout = validate cart + create order + create Stripe session in one `POST`); maps backend ProblemDetail errors to UI-friendly errors; validates input (zod) before forwarding; same-origin so no CORS needed from the browser; holds the JWT access/refresh tokens in httpOnly cookies and refreshes them; forwards the shopper's IP (`X-Forwarded-For`) and an `X-Request-Id` to the gateway; maps 429 to a friendly message.

## Revision 2 architecture: data, cache, gateway and payment consistency
Decisions made after Revision 1. They supersede the Revision 1 statements that carts live in Redis, that idempotency keys live in a Postgres table, and that customer authentication is out of v1 scope.

### Redis: idempotency, product cache, cart cache
- **Idempotency keys move from Postgres to Redis.** `SET idem:{scope}:{key} NX` with a JSON value `{status, requestHash, response}`; IN_PROGRESS marker with a short TTL (60 s), COMPLETED record with 24 h TTL. Same key + same hash → stored response; different hash → 422; marker present → 409.
- **Postgres is the correctness backstop** (Redis can't join the order transaction): add `orders.idempotency_key VARCHAR(64) UNIQUE` and `payments.idempotency_key VARCHAR(64) UNIQUE`. If Redis is down, or a record expired, a replay finds the existing order/payment by key and rebuilds the response (Stripe session fetched by the stored `stripe_checkout_session_id`), so no duplicate order can ever be created.
- There is **no `idempotency_keys` table** in Postgres (and no purge job for it); Redis TTLs expire the records.
- **Cart:** Postgres (`carts`, `cart_items`) is the source of truth. Redis is a cache-aside copy keyed by cart session token (TTL 7 d), evicted/refreshed on every cart mutation and on checkout. A Redis flush loses nothing.
- **Product/category read cache:** unchanged (`@Cacheable`, TTL ~10 min, evict on writes). Stock is still always read from Postgres.
- Redis outage: product and cart reads fall back to Postgres; idempotency falls back to the Postgres unique-key backstop.
- The schema change is made directly in `V1__baseline.sql` and `schema.sql` because no database had applied them yet (the Docker Postgres was empty and the backend had never started). Once any database has applied V1, changes must go in new `V<n>` migrations.

### Cassandra: order history and transaction log (via outbox)
- **Postgres** keeps live orders, payments and inventory. In the same transaction as each order/payment state change, insert a row in a new table `outbox_events` (`id`, `aggregate_type`, `aggregate_id`, `event_type`, `payload JSONB`, `created_at`, `published_at`, `attempts`). This keeps the existing webhook transaction atomic (payment + order + stock + outbox row).
- **`OutboxPublisher`** (scheduled, `SELECT ... FOR UPDATE SKIP LOCKED`, batch of N) projects unpublished events into Cassandra and sets `published_at`. Delivery is at-least-once; Cassandra writes are idempotent upserts keyed by the same primary key, so duplicates are harmless. Published rows are purged after 7 days (`db/ops/maintenance`).
- **No message broker (decided):** the polling publisher writes straight to Cassandra. It calls an `OrderEventSink` interface (v1 implementation: `CassandraOrderEventSink`), so a RabbitMQ or Kafka sink can be added later if a second consumer appears, without changing the outbox. Poll interval ~1 s, batch ~100, history lag is therefore about a second.
- **Cassandra tables** (`db/cassandra/schema.cql`, keyspace `planetm`, applied by a compose init step because Flyway doesn't manage Cassandra):
  - `orders_by_customer` — PK `((customer_id), placed_at DESC, order_id)`: summary rows for the "past orders" list.
  - `order_by_id` — PK `(order_id)`: full order snapshot with items and shipping.
  - `order_events_by_order` — PK `((order_id), event_time timeuuid)`: the transaction log (ORDER_PLACED, PAYMENT_SUCCEEDED/FAILED, STOCK_COMMITTED, ORDER_EXPIRED, ...).
- **Reads:** `GET /orders` (the logged-in customer's own history) and the new `GET /orders/{publicId}/events` read from Cassandra. `GET /orders/{publicId}` (used by the payment-success poll) stays on Postgres for fresh status. History may lag by seconds (eventually consistent); if Cassandra is down the list endpoint falls back to Postgres.
- **Stack:** `spring-boot-starter-data-cassandra`, `cassandra:5` container (heap capped for Docker Desktop, e.g. `MAX_HEAP_SIZE=512M`), Testcontainers Cassandra for the projector integration test only.

### nginx gateway and rate limiting
- New `nginx/nginx.conf` + `nginx` service in the backend repo's `docker-compose.yml`. Flow: **browser → Next.js BFF (server-side) → nginx → Spring Boot**. `BACKEND_URL` in the frontend points at the gateway (`http://localhost:8080` locally); Spring moves to `server.port=8081` and is **not published** to the host/public network. Postgres, Redis and Cassandra host ports are dev-only.
- **Routing:** `/api/v1/**` and `/webhooks/stripe` → Spring (`upstream` configurable: `host.docker.internal:8081` when Spring runs via `mvnw`, `backend:8081` when containerised). `/actuator/**` and (outside dev) `/swagger-ui` and `/v3/api-docs` are blocked.
- **Rate limiting (`limit_req_zone`, keyed on the real client IP):** because every request reaches nginx from the BFF's IP, the BFF forwards the shopper's IP in `X-Forwarded-For`, and nginx trusts it only from the BFF's own address (`set_real_ip_from` listed in `nginx/trusted-proxies.conf`, never whole private ranges). Dev trusts only the compose-network gateway (`trusted-proxies.dev.conf`, observed as 172.18.0.1); **production must mount a file listing only the BFF's real address(es)** (`trusted-proxies.prod.conf.example`). Requests from any other address have their `X-Forwarded-For` ignored, so a forged header cannot dodge the limits. Zones: general API ~10 r/s burst 20; cart ~5 r/s; checkout/payment ~2 r/s burst 5; webhook zone separate and lenient (Stripe retries; signature still verified in Spring). Over-limit → `429` with `Retry-After`; the BFF maps 429 to a friendly message.
- Also at the gateway: `client_max_body_size 1m`, upstream timeouts, `X-Request-Id` generated and passed through for log correlation, security headers; TLS termination is a production concern (dev stays HTTP).
- Frontend BFF change: `src/bff/backendClient` reads the incoming request's client IP and sends `X-Forwarded-For` and `X-Request-Id` on every backend call; handles 429.

### ACID and failure handling for payment data (Postgres = source of truth)
**Atomicity — what is inside one transaction**
- One `@Transactional(rollbackFor = Exception.class)` service method per state change (Spring rolls back only on unchecked exceptions by default, so checked ones must be listed). Transactions are opened in services, never controllers.
- A payment state change = one transaction containing: insert `processed_stripe_events`, guarded status update on `payments`, status update on `orders`, stock commit/release, `inventory_movements` rows, a `payment_events` audit row and the `outbox_events` row. Any exception rolls all of it back.
- **No network calls inside a DB transaction.** Stripe API calls and signature verification happen before/after, never while locks are held. Create-session flow: tx 1 commits the order (PENDING_PAYMENT), the stock reservation and a `payments` row (INITIATED, session id still NULL); the Stripe call runs outside any tx with the idempotency key, `client_reference_id = order public id` and `expires_at` = 30 min (the stock reservation lasts 35 min, so Stripe expires the session before our stock is released); tx 2 stores the Stripe session id on the payments row. A crash between the two leaves a PENDING order and payment that the webhook (matched through `client_reference_id`) or the reconciliation job resolves. A payment that succeeds after its order already expired is recorded as `LATE_PAYMENT`; the handler tries to re-reserve stock and, if that is impossible, flags the order for a manual refund in the Stripe dashboard (refund API is out of v1).
- Redis eviction runs in `afterCommit`; Redis, Cassandra or cache failures never roll back or fail a committed payment (they are logged and retried/ignored).

**Consistency — invariants enforced by the database, not only by code**
- Guarded transitions (compare-and-set): `UPDATE orders SET status='PAID' WHERE id=? AND status='PENDING_PAYMENT'`; zero rows updated = already handled or illegal transition, so the handler no-ops. A small state machine (in code and a `CHECK`) defines legal transitions; terminal states (PAID, REFUNDED, EXPIRED, CANCELLED) are never overwritten by late events (e.g. `payment_failed` after success, or `expired` racing `completed`).
- Before marking PAID, verify Stripe's `amount_total` and `currency` equal the order's; a mismatch does not mark PAID and records a `PAYMENT_MISMATCH` event for manual review.
- Existing constraints stay: partial unique index (one live payment per order), `CHECK`s on money and stock, FKs, `NUMERIC(12,2)` (never floats); money converted to Stripe minor units with `BigDecimal`.

**Isolation — concurrent webhooks, expiry job, user actions**
- Default `READ COMMITTED` plus explicit row locks: the handler does `SELECT ... FOR UPDATE` on the order (then payment, then inventory rows ordered by product id) so concurrent webhooks and the expiry job serialize. A single global lock order prevents deadlocks.
- `@Version` optimistic locking on `orders`, `payments`, `inventory` as a second guard. Serialization/deadlock errors (`40001`, `40P01`) and optimistic-lock failures are retried a bounded number of times with backoff; retried work is idempotent by construction.
- Session safety nets: `lock_timeout`, `statement_timeout`, `idle_in_transaction_session_timeout`, and `@Transactional(timeout=...)`; HikariCP `maxLifetime` shorter than any proxy/DB idle timeout so dropped connections fail fast and roll back.

**Durability**
- Keep `fsync` and `synchronous_commit=on` (defaults); production uses WAL archiving with point-in-time recovery, a synchronous standby, and scheduled restore tests of `db/ops/backup`. The app uses a least-privilege role (no DDL); Flyway uses a separate migration role. `payment_events`, `inventory_movements` and `processed_stripe_events` are append-only (UPDATE/DELETE revoked from the app role).

**Network and Stripe error handling**
- **Webhook response contract:** verify signature (400 on failure, nothing written) → run the transaction → return `2xx` only after commit. Any exception → `5xx`, so Stripe retries (exponential backoff for days). Duplicate events return `200` without side effects. Unknown event types are recorded and acknowledged with `200`.
- **Failure events** — `payment_intent.payment_failed`, `checkout.session.async_payment_failed` (Afterpay's asynchronous failure) and `checkout.session.expired` — each release the reservation and set FAILED/EXPIRED in one transaction. The shopper can retry with a new idempotency key; the partial unique index allows a new payment once the old one is FAILED/EXPIRED.
- **Timeouts and network errors to Stripe:** the outcome is treated as *unknown*, never as failure. The Stripe client uses `maxNetworkRetries` with the same idempotency key; if still unresolved the order stays PENDING_PAYMENT and the webhook or reconciliation job decides.
- **Network errors from the shopper's side:** the `Idempotency-Key` makes retries safe (Section 1).
- **Reconciliation job (recommended — remove if not wanted):** scheduled, finds PENDING_PAYMENT payments older than N minutes, fetches the Checkout Session from Stripe and applies the same transactional handler, recovering from lost webhooks. Out of scope for v1: refunds and disputes (state machine leaves room for `REFUNDED`).

**Schema additions:** `orders.version`, `payments.version` (BIGINT, `@Version`); `payment_events` (id, payment_id, stripe_event_id, event_type, from_status, to_status, payload JSONB, created_at; append-only); `PAYMENT_MISMATCH` as an event type.

### ACID compliance checklist (mandatory; each item has a test, see R18)
Division of work: **Postgres** provides rollback/commit, row locks, isolation, constraints and durability. **Spring** chooses transaction boundaries, requests locks, guards state changes, validates, retries and orders side effects. Neither is enough alone: constraints without the Java rules let wrong-but-valid state through; Java rules without constraints trust every code path to be bug-free. Each requirement below says what to implement and what breaks without it.

**R1 — One transaction per payment state change, rolling back on every exception (Atomicity)**
```java
@Transactional(rollbackFor = Exception.class, timeout = 10)
public void apply(Event event) { /* all DB work for one state change */ }
```
*Without it:* Spring rolls back only on unchecked exceptions, so a checked exception (e.g. `IOException`) would COMMIT a PAID order whose stock was never deducted.

**R2 — Transactional method in its own bean; no self-invocation (Atomicity)**
```java
@Service class PaymentWebhookService {          // retry wrapper: NOT transactional
    @Retryable(...) public void handle(Event e) { paymentTransaction.apply(e); }
}
@Service class PaymentTransaction {              // separate bean: @Transactional proxy applies
    @Transactional(rollbackFor = Exception.class) public void apply(Event e) { ... }
}
```
*Without it:* calling `this.apply()` bypasses the Spring proxy, so no transaction starts and each repository call commits on its own (partial updates). Swallowing an exception inside `apply` has the same effect: Spring sees a normal return and commits.

**R3 — Idempotent webhook insert that does not abort the transaction (Atomicity/Consistency)**
```java
@Modifying @Query(nativeQuery = true, value =
  "insert into processed_stripe_events(stripe_event_id, type) values (:id, :type) on conflict do nothing")
int insertIfAbsent(String id, String type);

if (processedEvents.insertIfAbsent(event.getId(), event.getType()) == 0) return;  // duplicate
```
*Without it:* catching a duplicate-key exception inside the transaction does not work on Postgres ("current transaction is aborted"), and committing the event row separately would make a failed attempt look "already processed", so Stripe's retry would never apply the payment. Inside the transaction, the row rolls back with everything else.

**R4 — No external calls inside a DB transaction (Atomicity/Isolation)**
```java
// tx 1 (short): order PENDING_PAYMENT + stock reservation + payments row INITIATED (session id NULL) -> commit
Session s = stripe.createSession(params, RequestOptions.builder().setIdempotencyKey(key).build()); // no tx open
// tx 2 (short): payments.stripe_checkout_session_id = s.getId()
```
*Without it:* a slow or timed-out Stripe call holds row locks and a pooled connection, blocking other orders and exhausting the pool; and Stripe can't be rolled back, so DB and Stripe diverge.

**R5 — Row lock, always in the same order (Isolation)**
```java
@Lock(LockModeType.PESSIMISTIC_WRITE)                       // SELECT ... FOR UPDATE
@QueryHints(@QueryHint(name = "jakarta.persistence.lock.timeout", value = "5000"))
@Query("select o from Order o where o.publicId = :publicId")
Optional<Order> findByPublicIdForUpdate(UUID publicId);
// lock order everywhere: orders -> payments -> inventory rows ORDER BY product_id
```
*Without it:* two concurrent webhooks both read PENDING_PAYMENT and deduct stock twice; locks taken in different orders (product 7 then 8 vs 8 then 7) deadlock (`40P01`).

**R6 — Guarded updates; continue only if exactly one row changed (Consistency/Isolation)**
```java
@Modifying(flushAutomatically = true, clearAutomatically = true)
@Query("update Order o set o.status = 'PAID' where o.id = :id and o.status = 'PENDING_PAYMENT'")
int markPaid(Long id);

if (orders.markPaid(order.getId()) == 0) return;   // already handled or illegal: do nothing
inventory.commitStock(order.getItems());
```
*Without it:* a late `payment_failed` can overwrite PAID, a replay can deduct stock twice. `clearAutomatically` is required because bulk updates bypass Hibernate's in-memory entities, which would otherwise show stale status.

**R7 — Legal state transitions in code and values in the database (Consistency)**
```java
public boolean canMoveTo(OrderStatus next) {
    return switch (this) {
        case PENDING_PAYMENT -> next == PAID || next == PAYMENT_FAILED || next == EXPIRED || next == CANCELLED;
        case PAYMENT_FAILED  -> next == PENDING_PAYMENT;
        case PAID            -> next == SHIPPED;
        case SHIPPED         -> next == DELIVERED;
        default              -> false;
    };
}
```
```sql
status VARCHAR(20) NOT NULL CHECK (status IN ('PENDING_PAYMENT','PAID','PAYMENT_FAILED','CANCELLED','EXPIRED','SHIPPED','DELIVERED'))
```
*Without it:* the `CHECK` only lists valid values, not valid moves; terminal states (PAID, DELIVERED, EXPIRED) could be reopened by out-of-order events.

**R8 — Optimistic locking as a second guard (Isolation)**
```java
@Entity class Order { @Version private long version; }   // UPDATE ... WHERE id=? AND version=?
```
```sql
ALTER TABLE orders   ADD COLUMN version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN version BIGINT NOT NULL DEFAULT 0;
```
*Without it:* any code path that forgets `FOR UPDATE` silently overwrites a concurrent change (lost update).

**R9 — Bounded retries for lock and version conflicts (Isolation)**
```java
@Retryable(retryFor = { PessimisticLockingFailureException.class,      // 40P01 deadlock, 55P03 lock timeout
                        OptimisticLockingFailureException.class,       // version conflict
                        CannotAcquireLockException.class },
           maxAttempts = 3, backoff = @Backoff(delay = 50, multiplier = 2, random = true))
```
*Without it:* a harmless deadlock or version conflict becomes a 5xx and a lost user action; unbounded retries would hammer the database. Safe only because R3 and R6 make the work repeatable.

**R10 — Verify amount and currency before marking PAID (Consistency)**
```java
BigDecimal paid = BigDecimal.valueOf(session.getAmountTotal()).movePointLeft(2);
if (paid.compareTo(order.getTotal()) != 0 || !order.getCurrency().equalsIgnoreCase(session.getCurrency())) {
    paymentEvents.save(PaymentEvent.mismatch(order, event));   // flag for manual review, do not mark PAID
    return;
}
```
*Without it:* a tampered or mis-priced session would mark an under-paid order PAID. Money is `NUMERIC(12,2)` / `BigDecimal`, never `double`.

**R11 — Database constraints as the last line of defence (Consistency)**
```sql
CONSTRAINT chk_inventory_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand),
quantity_on_hand INTEGER NOT NULL CHECK (quantity_on_hand >= 0),
CREATE UNIQUE INDEX uq_payments_one_live_per_order ON payments (order_id) WHERE status IN ('INITIATED','SUCCEEDED');
idempotency_key VARCHAR(64) UNIQUE   -- on orders and payments (Postgres backstop for Redis idempotency)
```
*Without it:* a Java bug can commit negative stock, two live payments for one order, or a duplicate order after Redis loses an idempotency record.

**R12 — Atomic conditional stock reservation (Consistency/Isolation)**
```java
@Modifying @Query("update Inventory i set i.quantityReserved = i.quantityReserved + :q " +
                  "where i.productId = :id and i.quantityOnHand - i.quantityReserved >= :q")
int reserve(Long id, int q);        // 0 rows -> throw OutOfStockException (409), whole checkout rolls back
```
*Without it:* check-then-update (read stock, compare in Java, write) lets two buyers reserve the last unit.

**R13 — Time limits so nothing hangs while holding locks (Isolation/Atomicity)** *(implemented in `db/migrations/V3__app_role_and_privileges.sql`)*
```sql
ALTER ROLE planetm_app SET lock_timeout = '5s';
ALTER ROLE planetm_app SET statement_timeout = '15s';
ALTER ROLE planetm_app SET idle_in_transaction_session_timeout = '30s';
```
```yaml
spring.datasource.hikari.max-lifetime: 1500000   # shorter than any proxy/DB idle timeout (ms)
```
*Without it:* a stuck transaction or a leaked connection holds row locks indefinitely and every later request for that order waits behind it.

**R14 — Webhook HTTP contract: 2xx only after commit (Durability/Atomicity)**
```java
try { event = Webhook.constructEvent(payload, signature, webhookSecret); }
catch (SignatureVerificationException e) { return ResponseEntity.badRequest().build(); }  // nothing written
paymentWebhookService.handle(event);        // exception -> 5xx -> Stripe retries with backoff
return ResponseEntity.ok().build();         // reached only after the service method (and its commit) returned
```
*Without it:* answering before the commit (e.g. via `@Async`) tells Stripe "done" for a payment that may then roll back; it is never retried and the payment is lost.

**R15 — Side effects that cannot roll back run after commit (Durability)**
```java
publisher.publishEvent(new PaymentCommitted(order.getId()));             // inside the transaction
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
void evictCaches(PaymentCommitted e) { /* Redis eviction; log failures, never undo the payment */ }
```
Cassandra is written only from the `outbox_events` row inserted in the same transaction (`outbox.save(OutboxEvent.orderPaid(order))`). *Without it:* a rollback after Redis was already evicted or an event already sent leaves caches and history describing a payment that never happened.

**R16 — Least privilege and append-only audit tables (Consistency/Durability)** *(implemented in `db/migrations/V3__app_role_and_privileges.sql`; Flyway runs as owner `planetm`, the app connects as `planetm_app`; every later migration that adds a table must include its GRANT lines)*
```sql
REVOKE UPDATE, DELETE, TRUNCATE ON payment_events, inventory_movements, processed_stripe_events FROM planetm_app;
REVOKE CREATE ON SCHEMA public FROM planetm_app;      -- Flyway uses a separate migration role
```
*Without it:* a bug or injection can rewrite payment history or drop tables.

**R17 — Durability settings (Durability)**
Keep `fsync=on` and `synchronous_commit=on` (defaults; never disable for this database). Production: WAL archiving for point-in-time recovery, a synchronous standby so a commit is acknowledged only after a replica has the data, and a scheduled restore test of `db/ops/backup`. *Without it:* an acknowledged payment can disappear after a crash or failover.

**R18 — Required tests (Testcontainers Postgres; WireMock for Stripe faults)**
```java
@Test void concurrentDuplicateWebhooksDeductStockOnce() throws Exception {
    var pool = Executors.newFixedThreadPool(2);
    var start = new CountDownLatch(1);
    var calls = List.of(submit(pool, start, event), submit(pool, start, event));
    start.countDown();
    for (var c : calls) c.get(10, TimeUnit.SECONDS);
    assertThat(inventory(7).onHand()).isEqualTo(25 - 2);          // deducted once
    assertThat(order(42).status()).isEqualTo(PAID);
    assertThat(count("payment_events", "order_id=42")).isEqualTo(1);
}

@Test void failureAfterOrderUpdateRollsBackEverything() {
    doThrow(new IOException("boom")).when(inventoryService).commitStock(any());   // checked exception
    assertThatThrownBy(() -> paymentTransaction.apply(event)).isInstanceOf(Exception.class);
    assertThat(order(42).status()).isEqualTo(PENDING_PAYMENT);
    assertThat(payment(42).status()).isEqualTo(INITIATED);
    assertThat(processedEventExists("evt_1")).isFalse();           // retry must still be applied
}
```
Also required: duplicate event no-op; late `payment_failed` after PAID ignored; amount mismatch not PAID; deadlock/version conflict retried and succeeds; Stripe timeout leaves order PENDING with stock intact; reconciliation recovers a lost webhook; Redis/Cassandra failure does not affect a committed payment; no Stripe call while a transaction is open (verified with a test double that asserts `TransactionSynchronizationManager.isActualTransactionActive() == false`).

## Database schema (PostgreSQL) — `planet-m-shop-backend/db/schema.sql`
`db/schema.sql` contains `CREATE TABLE` DDL (with PKs, FKs, CHECKs, UNIQUEs, indexes, `updated_at` triggers) for every table below; Flyway `V1__baseline.sql` is the same DDL and later changes are new `V<n>` files. Hibernate runs with `ddl-auto=validate`. Flyway (embedded `flyway-core` + `flyway-database-postgresql`, runs at app startup; no separate image) is the only thing that creates/changes tables; `schema.sql` is a reference kept in sync by `SchemaSyncTest`. All PKs `BIGINT GENERATED ALWAYS AS IDENTITY` (orders/payments also expose a UUID `public_id`); all tables have `created_at`, `updated_at`. Money in `NUMERIC(12,2)` plus `currency CHAR(3)`.

- **customers**: id, email (unique), first_name, last_name, phone, password_hash (nullable for guest), is_guest, role (CUSTOMER/ADMIN), failed_login_attempts, locked_until
- **refresh_tokens**: id, customer_id FK, token_hash, expires_at, revoked_at, created_at
- **shipping_addresses**: id, customer_id FK, full_name, line1, line2, city, state, postal_code, country (ISO-2), phone, is_default
- **categories**: id, name (unique), slug (unique), description
- **products**: id, sku (unique), name, description, category_id FK, price, currency, image_url, material, size, color, is_active
- **inventory**: id, product_id FK **unique**, quantity_on_hand CHECK ≥ 0, quantity_reserved CHECK ≥ 0, reorder_level, version (optimistic lock). CHECK (quantity_reserved ≤ quantity_on_hand). *Available = on_hand − reserved.*
- **carts**: id, customer_id FK nullable, session_token (unique, for guests), status (ACTIVE/CHECKED_OUT/ABANDONED), expires_at
- **cart_items**: id, cart_id FK, product_id FK, quantity CHECK > 0, unit_price_snapshot; UNIQUE(cart_id, product_id)
- **orders**: id, public_id UUID, customer_id FK, shipping_address_id FK (or snapshot columns copied at order time), status (PENDING_PAYMENT, PAID, PAYMENT_FAILED, CANCELLED, EXPIRED, SHIPPED, DELIVERED), subtotal, shipping_fee, tax, total, currency, placed_at, reservation_expires_at, idempotency_key (unique, nullable), version (`@Version`)
- **order_items**: id, order_id FK, product_id FK, sku, product_name (snapshot), unit_price, quantity, line_total
- **payments**: id, order_id FK, provider ('STRIPE'), payment_method (CARD / AFTERPAY), stripe_checkout_session_id (unique), partial unique index on (order_id) WHERE status IN ('INITIATED','SUCCEEDED') so an order can never have two live payments, stripe_payment_intent_id, amount, currency, status (INITIATED, SUCCEEDED, FAILED, EXPIRED, REFUNDED), failure_reason, idempotency_key (unique, nullable), version (`@Version`)
- **processed_stripe_events**: stripe_event_id PK, type, processed_at — webhook idempotency
- **payment_events** (append-only audit): id, payment_id FK, stripe_event_id, event_type (incl. PAYMENT_MISMATCH, LATE_PAYMENT), from_status, to_status, payload JSONB, created_at
- **outbox_events**: id, aggregate_type, aggregate_id, event_type, payload JSONB, created_at, published_at, attempts — written in the same transaction as the state change, projected to Cassandra by `OutboxPublisher`
- **inventory_movements** (audit): id, product_id, order_id, delta, reason (RESERVE, RELEASE, COMMIT, RESTOCK)

Idempotency keys themselves live in Redis (`idem:{scope}:{key}`); the unique `idempotency_key` columns on `orders` and `payments` are the Postgres backstop. Order history lives in Cassandra (`db/cassandra/schema.cql`).

Indexes: products(category_id, is_active), order_items(order_id), orders(customer_id, status), cart_items(cart_id), payments(order_id).

## REST API — documented in Swagger
**Every endpoint below is documented with springdoc-openapi**: Swagger UI at `/swagger-ui.html`, JSON at `/v3/api-docs`, YAML exported to `docs/openapi.yaml` (committed). Controllers carry `@Tag`, each method `@Operation(summary, description)` and `@ApiResponse` for every status it returns (200/201/204/400/404/409/422); DTOs carry `@Schema` (descriptions, examples, required); `Idempotency-Key` is declared as a required `@Parameter(in = HEADER)` on the order and payment endpoints; `ProblemDetail` error schema is shared; the Stripe webhook is documented (signature header `Stripe-Signature`). `OpenApiContractTest` fails the build if a controller endpoint is missing from the spec or `docs/openapi.yaml` is stale. Swagger UI is enabled in dev/test only. Tags: Products, Categories, Inventory, Customers, Shipping Addresses, Cart, Orders, Payments, Webhooks.
Base `/api/v1`. Errors use RFC-7807 `ProblemDetail` via `GlobalExceptionHandler`.

Gaps found in Revision 1: no checkout bill-preview or payment-methods endpoint, no categories BFF route (needed by the pills), no order-history/events or order-status BFF routes, no cart merge, no admin order/stock management, no way to authenticate (admin-only writes and per-customer order lists were unenforceable).

**Authentication (decided: customer accounts with JWT + admin role)**
- Spring Security OAuth2 resource server with Nimbus JWT (no extra library): `NimbusJwtEncoder` issues **access tokens (15 min)**; **refresh tokens (7 d)** are random, stored hashed in a new `refresh_tokens` table, rotated on use and revocable. Passwords hashed with BCrypt; failed-login counter and temporary lockout on `customers`. Signing key from env (`JWT_SECRET`).
- Roles: `CUSTOMER`, `ADMIN` (`customers.role`). Admins are seeded by an ops script/env, never via public registration. Guest checkout stays allowed (guest customer record); order history, saved addresses and `/customers/me` require login.
- **BFF holds the tokens:** access and refresh tokens are stored in `httpOnly`, `SameSite=Lax`, `Secure` (non-local) cookies, never exposed to browser JS; the BFF attaches `Authorization: Bearer` to backend calls and transparently refreshes on 401. Mutating BFF routes check `Origin`/`Host` (CSRF defence). Cart session cookie and auth cookies are separate; on login the guest cart is merged into the account cart.
- nginx adds a stricter `limit_req` zone for `/auth/*` (e.g. 5 r/min per client IP) against credential stuffing.
- Out of v1: email verification, password reset (needs an email service), social login, an admin UI (admins use Swagger/API; admin UI is a later revision), refunds, coupons, wishlists/reviews, order-confirmation emails.
- Schema additions: `customers.role`, `customers.failed_login_attempts`, `customers.locked_until`; `refresh_tokens` (id, customer_id, token_hash, expires_at, revoked_at, created_at).

**Backend endpoints** (`/api/v1`; every one documented in Swagger; auth: P = public, C = logged-in customer, A = admin, W = Stripe webhook signature)
| Area | Endpoint | Auth |
|---|---|---|
| Auth | `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout` | P (logout: C) |
| Customer | `GET/PUT /customers/me`, `PUT /customers/me/password` | C |
| Customer (admin) | `GET /customers`, `GET/PUT/DELETE /customers/{id}` | A |
| Addresses | `GET/POST /customers/me/addresses`, `PUT/DELETE /customers/me/addresses/{id}`, `PUT .../{id}/default` | C |
| Categories | `GET /categories`, `GET /categories/{id}` | P |
| Categories (admin) | `POST /categories`, `PUT/DELETE /categories/{id}` | A |
| Products | `GET /products?category=&q=&page=&size=&sort=`, `GET /products/{id}` | P |
| Products (admin) | `POST /products`, `PUT/DELETE /products/{id}` | A |
| Inventory | `GET /products/{id}/availability` | P |
| Inventory (admin) | `GET /inventory?lowStock=`, `GET/PUT /inventory/{productId}` | A |
| Cart | `GET /cart`, `POST /cart/items`, `PUT /cart/items/{productId}`, `DELETE /cart/items/{productId}`, `DELETE /cart`, `POST /cart/merge` (on login) | P (guest token) / C |
| Checkout | `POST /checkout/quote` (subtotal, shipping, tax, total, allowed payment methods), `GET /payments/methods?country=&total=` | P |
| Orders | `POST /orders/checkout` (+ `Idempotency-Key`), `GET /orders/{publicId}` (Postgres, fresh status), `GET /orders` (own history, Cassandra), `GET /orders/{publicId}/events` (transaction log, Cassandra), `PUT /orders/{publicId}/cancel` (PENDING_PAYMENT only) | P by unguessable publicId / C |
| Orders (admin) | `GET /admin/orders?status=&page=`, `PUT /admin/orders/{publicId}/status` (SHIPPED, DELIVERED, CANCELLED) | A |
| Payments | `POST /payments/checkout-session` (+ `Idempotency-Key`; also used to retry after failure), `GET /orders/{publicId}/payment` | P / C |
| Webhook | `POST /webhooks/stripe` | W |
| Ops | `GET /actuator/health` (internal only, blocked at nginx) | internal |

**BFF routes** (`app/api/**`, the only thing the browser calls): `auth/{register,login,logout,session}`, `account/{profile,addresses,password}`, `categories`, `products`, `products/[id]`, `cart` (+ `items`, `items/[productId]`, `merge`), `checkout/quote`, `payment-methods`, `orders/checkout`, `orders` (history), `orders/[id]` (status), `orders/[id]/events`, `orders/[id]/cancel`, `payments/checkout-session`. New pages: `/login`, `/register`, `/account`, `/account/orders`, `/account/orders/[id]`. Server-rendered pages read the auth cookie; protected pages redirect to `/login`.


## Key design decisions
1. **Redis scope**: idempotency keys, product/category read cache (`@Cacheable`, TTL ~10 min, evicted on writes), and a cart cache (cache-aside, TTL 7 d). Nothing else. Carts, orders and payments are stored in Postgres only; stock availability is always read from Postgres.
2. **Inventory correctness**: reservation at checkout via atomic conditional `UPDATE inventory SET quantity_reserved = quantity_reserved + :q WHERE product_id=:id AND quantity_on_hand - quantity_reserved >= :q` (0 rows ⇒ `OutOfStockException`), plus `@Version` as a backstop. Add-to-cart does a non-reserving availability check; checkout does the authoritative reservation. A scheduled job expires unpaid orders after 30 min and releases stock.
3. **Transactional payment write**: one transaction per state change with the guarded updates, row locks, retries and after-commit side effects defined in "Payment consistency (ACID)" (R1–R18).
4. **Payment redirect**: frontend calls the BFF `POST /api/payments/checkout-session` (which calls Spring `POST /payments/checkout-session`), receives `{sessionId, url}`, loads Stripe via `loadStripe(publishableKey)` and redirects the browser to Stripe's hosted page; `success_url`/`cancel_url` return to `/payment/success?order=` and `/payment/cancel`. The success page polls `GET /orders/{id}` until status is PAID (the webhook, not the redirect, is the source of truth). Stripe secret/webhook keys come from env vars, never committed.
5. **Price integrity**: server recomputes totals from DB prices; the client total is display-only. Totals = Σ line_total + shipping_fee + tax.
6. **Security**: JWT accounts with CUSTOMER and ADMIN roles (see Authentication); CORS not needed because the browser only talks to the same-origin BFF; input validation on all DTOs; admin endpoints require the ADMIN role.
7. **Redux state**: slices `catalogue`, `cart`, `checkout`; RTK Query for client-side server data (pointing at the BFF `/api/*`); cart slice mirrors the server cart; the guest session token lives in an `httpOnly` cookie set by the BFF (not `localStorage`). Stripe webhooks go directly to Spring (`/webhooks/stripe`), not through the BFF.
8. **Caches**: Redis in Spring (product reads, carts), Next fetch cache/ISR (SSR data), Redux (client UI state). Writes evict Redis and call `revalidateTag` in the BFF.
9. **Payment methods (Card + Afterpay) — no extra library needed**: Afterpay (branded Clearpay in UK/EU) is a native Stripe payment method (`afterpay_clearpay`), so the existing `stripe-java` (backend) and `@stripe/stripe-js` (frontend) cover both options; no separate Afterpay SDK. The checkout page has a payment-method form (radio cards: "Credit / Debit card", "Afterpay") whose selection is sent to the backend, which creates the Checkout Session with `payment_method_types = [card]` or `[afterpay_clearpay]` (and `shipping_address_collection` / prefilled shipping, which Afterpay requires). Constraints handled in code and surfaced in the UI: Afterpay is only offered when currency/shipping country are supported (US, CA, AU, NZ, UK, and Stripe-supported EU markets, configurable in `application.yml`) and when the order total is within Afterpay's min/max limits (configurable; otherwise the option is disabled with an explanatory hint). Afterpay is asynchronous-confirmation, so the webhook-as-source-of-truth design applies to both methods. Requires Afterpay to be enabled in the Stripe Dashboard (test mode works).
10. **Idempotency for Place order / payment API**: the client generates a UUID `Idempotency-Key` when the checkout page loads (kept in the checkout slice, regenerated only after a terminal failure or cart change) and the BFF forwards it. Backend `IdempotencyService` stores `idem:{scope}:{key}` in Redis (`SET NX`): IN_PROGRESS marker (60 s) → concurrent duplicate gets `409`; COMPLETED record (24 h) with the request hash and response → same key + same payload returns the stored response (same order id, same Stripe URL, no second order, reservation or Session); same key + different payload → `422`. Redis cannot join the order transaction, so Postgres is the backstop: unique `idempotency_key` columns on `orders` and `payments`; if Redis is down or the record expired, a replay finds the existing order by key and rebuilds the response. The key is also sent to Stripe as the request `Idempotency-Key`. The UI disables "Place order" while a request is pending.
11. **Order history via outbox**: Postgres stays the system of record; each order/payment change inserts an `outbox_events` row in the same transaction; a polling `OutboxPublisher` writes to Cassandra (no message broker; `OrderEventSink` interface allows RabbitMQ/Kafka later).
12. **Gateway**: browser → BFF → nginx → Spring; Spring is not published; rate limits per real client IP forwarded by the BFF.

## Gherkin requirements (the TDD spec)
Feature files live in each repo's `features/` folder: scenarios tagged `@backend` in the backend repo, `@frontend` in the frontend repo (scenarios tagged both are written in both). Add to backend: **swagger.feature** — every endpoint appears in `/v3/api-docs` with summary and responses; `Idempotency-Key` is listed as a required header on order/payment operations; `docs/openapi.yaml` matches the generated spec @backend. Add to backend: **schema.feature** — `db/schema.sql` creates all tables and matches Flyway migrations @backend.
Each scenario maps to ≥1 unit test; tags `@backend`, `@frontend` say where it is implemented.

**bff-ssr.feature** (new)
- Product list page is server-rendered: the initial HTML contains product names and prices without client JS @frontend
- Product detail page is server-rendered with title/description metadata; unknown id renders the 404 page @frontend
- BFF `GET /api/products` proxies the backend and maps DTOs to the UI model @frontend
- BFF maps backend errors (404, 409 out-of-stock, 400 validation) to the right status and message @frontend
- BFF never exposes backend URL or Stripe secret in responses @frontend
- BFF sets an httpOnly cart-session cookie on first cart write and forwards it on later calls @frontend
- BFF rejects invalid payloads (zod) with 400 before calling the backend @frontend
- Product change triggers cache revalidation of the SSR product pages @frontend

**catalogue.feature**
- Show all active products with name, image, price @frontend @backend
- Category pill widgets are rendered above the grid: an "All" pill plus one pill per category. Categories are generic, by furniture area: Bedroom, Dining, Living, Outdoor (seeded in V2; admin-editable via the categories CRUD; there is no separate Sofa pill). Specific items such as bed sheets, dining runners, and cushion covers and sofa sets (under Living) are products inside these categories @frontend
- Clicking a pill filters the grid to that category, marks the pill active (`aria-pressed`) and updates the URL (`?category=living`) so the SSR page is shareable/bookmarkable @frontend
- Clicking "All" or the active pill again clears the filter @frontend
- Pills are keyboard accessible and wrap/scroll horizontally on mobile @frontend
- Category with no products shows the empty state while the pill stays selected @frontend
- Filter by category on the API (e.g. category "Living" returns cushion covers and sofa sets) @backend
- Search by product name @backend
- Paginate when more than a page of products exist @backend
- Show an empty-state message when no products match @frontend
- Show "Out of stock" badge and disabled Add button when available stock is 0 @frontend
- Show loading spinner while fetching; show error banner and Retry when the API fails @frontend
- Product detail by id; unknown id returns 404 @backend

**cart.feature**
- Add an in-stock product to an empty cart @frontend @backend
- Adding the same product again increases quantity @backend
- Reject adding more than available stock ("Only N left") @frontend @backend
- Reject adding an out-of-stock product @backend
- Reject quantity ≤ 0 @backend
- Update item quantity within stock; remove an item; clear the cart @frontend @backend
- Cart badge in header shows total item count @frontend
- Cart totals recalculate after every change @frontend @backend
- Cart persists across page reload (session token) @frontend

**checkout.feature**
- Show line items and the total bill (subtotal + shipping + tax) @frontend @backend
- Shipping form requires name, address line 1, city, state, postal code, country, phone, valid email @frontend @backend
- Show inline validation errors and block submit on invalid input @frontend
- Payment-method form lists "Credit / Debit card" and "Afterpay" as radio options; card is preselected @frontend
- Selecting Afterpay shows a short "pay in instalments" note; "Place order" sends `paymentMethod=AFTERPAY` @frontend
- Afterpay is disabled with a hint when the order total is outside its min/max or the shipping country/currency is unsupported @frontend @backend
- Place order is blocked until a payment method is chosen and shipping details are valid @frontend
- Backend rejects an unknown or unsupported payment method with 400 @backend
- Block checkout on an empty cart @frontend @backend
- Creating the order reserves inventory and sets status PENDING_PAYMENT @backend
- Checkout fails with a clear message if an item became unavailable since it was added @backend
- Server ignores client-supplied prices and recomputes the total @backend
- Guest checkout creates a guest customer; returning email reuses the customer @backend

**payment.feature**
- Click "Pay now" redirects the browser to the Stripe-hosted page @frontend
- Backend creates a Stripe Checkout Session with the correct amount and currency @backend
- Card selection creates a Session with `payment_method_types=[card]`; Afterpay selection with `[afterpay_clearpay]` @backend
- Place order without an `Idempotency-Key` header returns 400 @backend
- Repeating Place order with the same key and payload returns the original order and Stripe URL; no second order, stock reservation or Stripe Session is created @backend
- Same key with a different payload returns 422 @backend
- Two simultaneous requests with the same key: one proceeds, the other gets 409 and can safely retry @backend (integration/Testcontainers)
- The idempotency key is forwarded to Stripe as the request `Idempotency-Key` @backend
- A failed first attempt (e.g. out of stock) stores no completed record, so a retry with a new cart state is processed afresh @backend
- Double-clicking "Place order" sends one request (button disabled while pending) and the same key is reused on a network retry @frontend
- A new key is generated after a terminal failure or when the cart changes @frontend
- Stripe `checkout.session.completed` webhook marks payment SUCCEEDED, order PAID and commits stock — all in **one transaction** @backend
- If any step of the status update fails, the transaction rolls back (payment, order, inventory unchanged) @backend
- Duplicate webhook delivery is processed once (idempotent) @backend
- Webhook with an invalid signature returns 400 and changes nothing @backend
- `payment_intent.payment_failed` marks payment FAILED, order PAYMENT_FAILED and releases the reservation @backend
- Cancelled/abandoned checkout leaves the order PENDING_PAYMENT; the expiry job cancels it and releases stock after the timeout @backend
- Success page shows order confirmation once the order is PAID; shows "processing" while pending @frontend
- Cancel page offers a way back to the cart @frontend

**inventory.feature**
- Available = on-hand − reserved @backend
- Concurrent reservations of the last unit: exactly one succeeds @backend (integration/Testcontainers)
- Release restores availability; stock never goes negative @backend
- Admin can set stock; change evicts the product cache @backend

**customer.feature / product-admin.feature**
- CRUD for customers, shipping addresses, products and categories (create, read, update, delete, not-found, validation errors, duplicate email/SKU → 409) @backend

**caching.feature**
- Second read of the product list is served from Redis without hitting the repository @backend
- Updating or deleting a product evicts its cache entries @backend
- Cache failure (Redis down) falls back to the database @backend


### Revision 2 scenarios (added to the lists above)
- **backend `auth.feature` (new):** register with valid data; duplicate email 409; weak password 400; login returns tokens; wrong password 401 and failed counter increments; lockout after N failures; refresh rotates the token and the old one is rejected; logout revokes; expired access token 401; customer cannot read another customer's orders/addresses (403/404); non-admin gets 403 on admin endpoints; admin can manage products, stock and orders.
- **backend `checkout-quote.feature` (new):** quote returns subtotal, shipping, tax, total; Afterpay listed only inside limits and supported countries; quote ignores client prices; empty cart rejected.
- **backend `admin-orders.feature` (new):** admin lists/filters orders and moves PAID → SHIPPED → DELIVERED; illegal transitions rejected; customer cancel only while PENDING_PAYMENT; cart merge on login combines quantities within stock.
- **frontend `auth.feature` and `account-orders.feature` (new):** register/login forms validate and show errors; tokens are never readable by JS (httpOnly cookies); expired access token is refreshed transparently; protected pages redirect to `/login`; login merges the guest cart; account page lists past orders newest-first and shows an order's event timeline; checkout page shows the quote total before the order is placed.
- **backend `payment-consistency.feature` (new): failure at any step (payment, order, stock, audit or outbox write) rolls back all of them; checked exception also rolls back; two concurrent webhooks for one order produce one effect; late `payment_failed` after PAID is ignored; `expired` racing `completed` ends in one terminal state; amount or currency mismatch is not marked PAID and is flagged; webhook returns 5xx on DB failure and Stripe's retry then succeeds; duplicate retry returns 200 with no changes; async Afterpay failure releases stock; Stripe timeout leaves the order PENDING and no stock is lost; reconciliation recovers a lost webhook; deadlock/serialization failure is retried and succeeds; no Stripe call is made while a DB transaction is open; Redis/Cassandra failure does not affect the committed payment.
- **backend `idempotency.feature` (additional scenarios):** Redis stores the key; replay after Redis flush returns the original order via the Postgres unique key; Redis down still prevents duplicates; IN_PROGRESS marker → 409; TTL expiry.
- **backend `cart.feature` / `caching.feature` (additional scenarios):** cart survives a Redis flush; cart cache refreshed on every mutation and evicted on checkout; Redis outage falls back to Postgres.
- **backend `order-history.feature` (new):** paid order appears in Cassandra history after the outbox publishes; history list is newest-first; events endpoint returns the transaction log in order; Cassandra down falls back to Postgres; history is empty for customers with no orders.
- **backend `outbox.feature` (new):** outbox row written in the same transaction as the payment update; rolled back with it on failure; publisher marks rows published; duplicate delivery is idempotent; failed publish retries with an attempts counter; two publishers never process the same row.
- **backend `gateway.feature` (new, verified by a compose smoke script):** Spring port not reachable directly; request over the limit gets 429; limits apply per forwarded client IP, not per BFF; `/actuator` blocked; `X-Request-Id` passed through.
- **frontend `bff-ssr.feature` / `payment.feature` (additional scenarios):** BFF forwards client IP and request id; BFF shows a friendly message on 429.


## Testing strategy
**Backend (`backend/src/test`)**
- *Unit*: JUnit 5 + Mockito (`@ExtendWith(MockitoExtension.class)`) + AssertJ for `ProductService`, `CartService`, `InventoryService`, `OrderService`, `PaymentService` (verify with `InOrder`, `ArgumentCaptor`; rollback tested by making a mocked repository throw and asserting the Spring `@Transactional` proxy rolls back in an integration slice).
- *Web slice*: `@WebMvcTest` + MockMvc + `@MockitoBean` for each controller (status codes, validation, ProblemDetail bodies, webhook signature).
- *Repository slice*: `@DataJpaTest` with Testcontainers Postgres (real constraints, conditional update query).
- *Integration*: `@SpringBootTest` + Testcontainers (Postgres + Redis; Cassandra only for the outbox projector) for cache behaviour, concurrent reservation, the transactional webhook and all payment-consistency scenarios (R18); Stripe is mocked behind a `PaymentGateway` interface (WireMock for HTTP-level).
- *Cucumber-JVM* (`cucumber-spring`, `cucumber-junit-platform-engine`) runs `@backend` scenarios from `/features` against service-layer steps with mocks.
- Coverage gate with JaCoCo (≥ 80% lines on service packages).

**Frontend (`frontend/src`)**
- Jest (`next/jest`) + React Testing Library with `renderWithProviders` (Redux store; `next/navigation` mocked — no React Router); MSW for API. Async server components are tested by awaiting the component function and rendering its result with `backendClient` mocked; `app/api/**/route.ts` handlers are invoked directly with `Request` objects in the `node` environment; `user-event` for interaction; `jest-cucumber` binds `@frontend` scenarios to step files in `__tests__/`.
- Slice unit tests (reducers/selectors), component tests (ProductCard, CartItemRow, ShippingForm validation, PaymentRedirect with `loadStripe` mocked), page-level flows (catalogue → add to cart → checkout → redirect).
- Stripe redirect asserted via mocked `window.location.assign` / `stripe.redirectToCheckout` mock.


## Build order (TDD, each step starts with its `.feature` scenarios and failing tests)
1. Scaffolding: the two repos, Docker Compose (Postgres, Redis, Cassandra + init, nginx) in the backend repo, `db/schema.sql` + seed + Flyway baseline, `db/cassandra/schema.cql`, Spring Boot + Next.js (App Router)/Tailwind/Jest/RTL skeletons, CI workflow running both test suites.
2. Backend: auth (register/login/refresh/logout, roles) → categories/products CRUD + Redis product cache → inventory service.
3. Backend: customers + shipping addresses → Postgres cart + Redis cart cache + cart merge.
4. Backend: checkout quote, orders (Redis idempotency + Postgres backstop, atomic stock reservation), Stripe gateway, checkout-session endpoint, transactional webhook (R1–R18), outbox + Cassandra projector, expiry job, reconciliation job.
5. Backend: order history/events endpoints, admin order and stock endpoints.
6. Frontend: BFF `backendClient` + route handlers → SSR catalogue/product pages with category pills → store + cart → auth pages → checkout (quote, shipping, payment method) → payment redirect + success/cancel → account order history.
7. End-to-end smoke (Playwright, optional) with Stripe test mode and `stripe listen` forwarding webhooks through nginx; gateway smoke script; polish, docs, OpenAPI.

## Verification (end-to-end)
- Open `http://localhost:8080/swagger-ui.html` and confirm every endpoint (incl. Idempotency-Key header) is listed and callable.
- `cd planet-m-shop-backend && ./mvnw verify` — unit, slice, Testcontainers integration and Cucumber suites all green; JaCoCo gate passes.
- `cd planet-m-shop-frontend && npm test` — all Jest/RTL/jest-cucumber suites green; `npm run build` (Next production build) and `npm run lint` pass. `curl localhost:3000/products` shows product names in the raw HTML (confirms SSR).
- `docker compose up -d` brings up postgres, redis, cassandra (+ init) and nginx healthy; `docker compose exec cassandra cqlsh -e "DESCRIBE KEYSPACE planetm"` shows the three tables; `docker run --rm -v $PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro nginx nginx -t` passes; Spring's port 8081 is not reachable from outside, only nginx on 8080; hammering `/api/v1/orders/checkout` returns 429.
- Payment-consistency suite (R18) green: concurrent duplicate webhooks deduct stock once; a checked exception after the order update rolls everything back.
- `docker compose up` then walk through manually: browse catalogue → add item (try exceeding stock to see the error) → checkout form shows the correct total → Pay now redirects to Stripe test checkout (card `4242 4242 4242 4242`) → return to the success page → verify in Postgres that `payments`, `orders`, `inventory` and `inventory_movements` changed together; replay the webhook with `stripe events resend` and confirm no double-decrement; check `redis-cli KEYS 'products*'` shows cache entries that disappear after a product update.

## Open items to confirm before building
- "`/app` directory" is interpreted as Next.js App Router at `frontend/app/` (BFF handlers in `frontend/app/api/`); the Spring Boot API stays a separate service.
- Stripe Checkout (hosted redirect, recommended) vs. embedded Elements — plan assumes hosted redirect as requested.
- Currency/tax/shipping fee rules (plan assumes a single currency, flat shipping fee, configurable tax rate).
- Cassandra adds operational weight (memory, a third datastore); the outbox design keeps it removable because Postgres holds all the data.
- Rate limits are starting values; tune after load testing. The reconciliation job is a recommendation and can be removed.
- Out of v1: email verification, password reset, social login, an admin UI, refunds/disputes, coupons, wishlists/reviews, order-confirmation emails.
- Further plan updates from the owner will be applied as Revision 3 using the same merge procedure.
