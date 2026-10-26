# Planet-M Shop — Project Plan

## Context
Planet-M Shop is a greenfield e-commerce site for a furniture-linens company (bed sheets, cushion covers, sofa sets, dining runners, etc.). The working directory is empty, so this plan defines everything from scratch: repo layout, stack, database schema, REST API, caching, payment flow, and a **Gherkin-first (TDD) test suite that acts as the requirements**. Implementation follows the Gherkin scenarios: write feature file → write failing unit tests → implement → green.

Scope (v1): (1) product catalogue, (2) add-to-cart with inventory checks, (3) checkout with bill total + shipping form, (4) payment via redirect to Stripe, with payment status persisted transactionally. Basic CRUD API for all core entities.

## Tech stack
| Layer | Choice |
|---|---|
| Frontend + BFF | Next.js (App Router, `/app` directory) + React + TypeScript, Redux Toolkit (+ RTK Query), Tailwind CSS, `@stripe/stripe-js`. Routing is Next's file-system router (no React Router). Product pages are server-side rendered (React Server Components). The BFF layer is Next Route Handlers under `app/api/**` |
| Backend | Java 21, Spring Boot 3.x, Maven, Spring Web, Spring Data JPA, Bean Validation, springdoc-openapi, MapStruct |
| DB | PostgreSQL 16, migrations via Flyway |
| Cache | Redis 7 via Spring Cache (`@Cacheable`/`@CacheEvict`) + `GenericJackson2JsonRedisSerializer`; cart state also in Redis for guests |
| Payments | Stripe Checkout (hosted page). Backend creates a Checkout Session; frontend redirects to it; Stripe webhook confirms payment |
| Frontend tests | Jest via `next/jest`, React Testing Library, `@testing-library/user-event`, MSW (API mocking), `jest-cucumber` (runs Gherkin); BFF route handlers tested in Jest `node` environment |
| Backend tests | JUnit 5, Mockito, AssertJ, `@WebMvcTest` + MockMvc, `@DataJpaTest`, Testcontainers (Postgres, Redis), Cucumber-JVM, JaCoCo, WireMock/Stripe mocks |
| Local infra | Docker Compose (postgres, redis, backend, frontend) |

## Environment prerequisites (macOS, Apple Silicon — checked on this machine)
Persistence stays as planned: Spring Data JPA on Hibernate (implicit via `spring-boot-starter-data-jpa`), no change.

| Tool | Needed | Found on machine | Action | Who |
|---|---|---|---|---|
| JDK | 21 LTS (decided; project pinned via `<java.version>21</java.version>`). LTS = Long-Term Support: years of security patches; installed 23 is non-LTS and no longer patched | OpenJDK 23.0.2 (stays installed, untouched) | `brew install --cask temurin@21` (or asdf), then select 21 for this project via `JAVA_HOME` | Claude (non-risky) or you |
| Maven | 3.9+ | 3.9.9 | None (or use the `./mvnw` wrapper) | — |
| Node.js | 20.9+ (22 LTS recommended) for Next.js | 21.5.0 via asdf (too old / non-LTS; warns about `NODE_OPTIONS=--use-system-ca`) | `asdf install nodejs 22.x` then `asdf set nodejs 22.x` (21.5.0 stays installed) | Claude (non-risky) or you |
| npm | 10+ | 10.2.4 | None (ships with Node 22) | — |
| Docker Desktop + Compose v2 | Postgres 16, Redis 7, Testcontainers | CLI 27.3.1, Compose v2.30.3 installed, **daemon not running** | Launch Docker Desktop | You |
| PostgreSQL / Redis | via Docker Compose containers | Not installed locally | Nothing to install locally | — |
| Stripe CLI | Forward test webhooks (`stripe listen --forward-to localhost:8080/webhooks/stripe`) | Missing | `brew install stripe/stripe-cli/stripe`, then `stripe login` | Claude installs; you run `stripe login` (browser auth) |
| Stripe account + test keys | Publishable key, secret key, webhook signing secret | — | Create account at stripe.com, copy **test-mode** keys into `.env` files (never committed) | You |
| Git, Homebrew, gh, curl | VCS and tooling | All present | None | — |

**What Claude can do (non-risky, only after plan approval):** install Node 22 via asdf, JDK 21 (optional), Stripe CLI via Homebrew; run version checks; scaffold the project, generate `.env.example` files, and run builds/tests. All installs are user-level and reversible.
**What you do yourself:** start Docker Desktop; create the Stripe account and paste test keys into local `.env` files; `stripe login`; any system-level/admin installs. Claude never enters credentials or keys.
**Automatic via the project:** all Maven and npm dependencies (Spring Boot, Hibernate, Flyway, Mockito, Cucumber, Next.js, Tailwind, Redux Toolkit, Jest, RTL, etc.) and the Postgres/Redis containers via `docker compose up`.

## Repository layout — two repositories
**`planet-m-shop-backend`** (Spring Boot API + database scripts) and **`planet-m-shop-frontend`** (Next.js UI + BFF). Independent repos, independent CI and release cycles; they integrate only through the REST contract (the OpenAPI spec the backend publishes) and shared env var names.

**Do we need a third repo for SQL scripts (including frequently-run procedures and backup scripts)? No — still not required.** Scripts are backed up by git itself: the backend repo's remote (GitHub) is the backup, with history and review. Operational SQL that is run repeatedly lives in a `db/ops/` folder of the backend repo (see tree): `procedures/` (stored procedures/functions, applied through Flyway repeatable `R__*.sql` migrations so they are versioned and re-applied when changed), `maintenance/` (purge expired idempotency keys, expire unpaid orders, low-stock report, reconcile reserved vs. open orders) and `backup/` (`pg_dump` / restore shell scripts). Business logic stays in Java services and scheduled jobs rather than stored procedures; use procedures only for set-based maintenance. Note the *data* backups (dump files) are not stored in git; they go to object storage / managed-Postgres snapshots. The backend is the only service that owns and writes to the database, so the schema must version, review and deploy together with the entity/Flyway code that depends on it; a separate SQL repo would add sync overhead and the risk of schema/code drift. A third repo is only worthwhile if several services share one database or a separate DBA/ops team owns schema releases and backups with its own access controls — neither applies today; revisit if that changes. SQL therefore lives in `planet-m-shop-backend/db/`. (Can be split out later with `git subtree split` if needed.)

### Repo 1 — `planet-m-shop-backend`
```
planet-m-shop-backend/
├── README.md
├── docker-compose.yml            # postgres:16 (plain image, no SQL mounts; Flyway embedded in the backend creates the schema on startup, no Flyway container), redis:7, backend (frontend repo's compose points here)
├── .env.example                  # DB_URL, REDIS_HOST, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
├── features/                     # Gherkin requirements tagged @backend (source of truth for backend tests)
│   ├── catalogue.feature, cart.feature, checkout.feature, payment.feature, idempotency.feature
│   ├── inventory.feature, customer.feature, product-admin.feature, caching.feature
├── db/
│   ├── schema.sql                # full DDL for ALL tables, constraints and indexes (canonical, readable reference)
│   ├── seed.sql                  # categories (Bedroom, Dining, Living, Outdoor) + sample products/inventory
│   ├── ops/                      # frequently-run SQL: procedures/ (R__*.sql repeatable), maintenance/, backup/ (pg_dump/restore scripts + README)
│   └── migrations/               # Flyway: V1__baseline.sql (= schema.sql), V2__seed.sql, later incremental changes
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
    │   ├── checkout/page.tsx     # bill + shipping form + payment-method form (client)
    │   ├── payment/
    │   │   ├── success/page.tsx
    │   │   └── cancel/page.tsx
    │   └── api/                  # BFF route handlers (browser talks ONLY to these)
    │       ├── products/route.ts, products/[id]/route.ts
    │       ├── cart/route.ts, cart/items/route.ts, cart/items/[productId]/route.ts
    │       ├── orders/checkout/route.ts, orders/[id]/route.ts
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

**BFF responsibilities:** hides the Spring base URL and Stripe keys from the browser; manages the guest cart session token in an `httpOnly` cookie; aggregates calls (e.g. checkout = validate cart + create order + create Stripe session in one `POST`); maps backend ProblemDetail errors to UI-friendly errors; validates input (zod) before forwarding; same-origin so no CORS needed from the browser.

## Database schema (PostgreSQL) — `planet-m-shop-backend/db/schema.sql`
`db/schema.sql` contains `CREATE TABLE` DDL (with PKs, FKs, CHECKs, UNIQUEs, indexes, `updated_at` triggers) for every table below; Flyway `V1__baseline.sql` is the same DDL and later changes are new `V<n>` files. Hibernate runs with `ddl-auto=validate`. Flyway (embedded `flyway-core` + `flyway-database-postgresql`, runs at app startup; no separate image) is the only thing that creates/changes tables; `schema.sql` is a reference kept in sync by `SchemaSyncTest`. All PKs `BIGINT GENERATED ALWAYS AS IDENTITY` (orders/payments also expose a UUID `public_id`); all tables have `created_at`, `updated_at`. Money in `NUMERIC(12,2)` plus `currency CHAR(3)`.

- **customers**: id, email (unique), first_name, last_name, phone, password_hash (nullable for guest), is_guest
- **shipping_addresses**: id, customer_id FK, full_name, line1, line2, city, state, postal_code, country (ISO-2), phone, is_default
- **categories**: id, name (unique), slug (unique), description
- **products**: id, sku (unique), name, description, category_id FK, price, currency, image_url, material, size, color, is_active
- **inventory**: id, product_id FK **unique**, quantity_on_hand CHECK ≥ 0, quantity_reserved CHECK ≥ 0, reorder_level, version (optimistic lock). CHECK (quantity_reserved ≤ quantity_on_hand). *Available = on_hand − reserved.*
- **carts**: id, customer_id FK nullable, session_token (unique, for guests), status (ACTIVE/CHECKED_OUT/ABANDONED), expires_at
- **cart_items**: id, cart_id FK, product_id FK, quantity CHECK > 0, unit_price_snapshot; UNIQUE(cart_id, product_id)
- **orders**: id, public_id UUID, customer_id FK, shipping_address_id FK (or snapshot columns copied at order time), status (PENDING_PAYMENT, PAID, PAYMENT_FAILED, CANCELLED, EXPIRED, SHIPPED, DELIVERED), subtotal, shipping_fee, tax, total, currency, placed_at, reservation_expires_at
- **order_items**: id, order_id FK, product_id FK, sku, product_name (snapshot), unit_price, quantity, line_total
- **payments**: id, order_id FK, provider ('STRIPE'), payment_method (CARD / AFTERPAY), stripe_checkout_session_id (unique), partial unique index on (order_id) WHERE status IN ('INITIATED','SUCCEEDED') so an order can never have two live payments, stripe_payment_intent_id, amount, currency, status (INITIATED, SUCCEEDED, FAILED, EXPIRED, REFUNDED), failure_reason
- **processed_stripe_events**: stripe_event_id PK, type, processed_at — webhook idempotency
- **idempotency_keys**: idempotency_key (PK, UUID string), scope (`PLACE_ORDER` / `CREATE_PAYMENT_SESSION`), customer/session ref, request_hash (SHA-256 of canonical payload), status (IN_PROGRESS / COMPLETED), response_status, response_body (JSONB), order_id, created_at, expires_at (24h; purged by scheduled job)
- **inventory_movements** (audit): id, product_id, order_id, delta, reason (RESERVE, RELEASE, COMMIT, RESTOCK)

Indexes: products(category_id, is_active), order_items(order_id), orders(customer_id, status), cart_items(cart_id), payments(order_id).

## REST API (CRUD baseline + flows) — documented in Swagger
**Every endpoint below is documented with springdoc-openapi**: Swagger UI at `/swagger-ui.html`, JSON at `/v3/api-docs`, YAML exported to `docs/openapi.yaml` (committed). Controllers carry `@Tag`, each method `@Operation(summary, description)` and `@ApiResponse` for every status it returns (200/201/204/400/404/409/422); DTOs carry `@Schema` (descriptions, examples, required); `Idempotency-Key` is declared as a required `@Parameter(in = HEADER)` on the order and payment endpoints; `ProblemDetail` error schema is shared; the Stripe webhook is documented (signature header `Stripe-Signature`). `OpenApiContractTest` fails the build if a controller endpoint is missing from the spec or `docs/openapi.yaml` is stale. Swagger UI is enabled in dev/test only. Tags: Products, Categories, Inventory, Customers, Shipping Addresses, Cart, Orders, Payments, Webhooks.
Base `/api/v1`. Errors use RFC-7807 `ProblemDetail` via `GlobalExceptionHandler`.
- **Products**: `GET /products?category=&q=&page=&size=` · `GET /products/{id}` · `POST` · `PUT /{id}` · `DELETE /{id}` (soft delete via is_active)
- **Categories**: full CRUD `/categories`
- **Inventory**: `GET /inventory/{productId}` · `PUT /inventory/{productId}` (set/adjust stock)
- **Customers**: `POST /customers` · `GET/PUT/DELETE /customers/{id}`
- **Shipping addresses**: CRUD `/customers/{id}/addresses`
- **Cart**: `GET /cart` · `POST /cart/items` {productId, qty} (inventory check) · `PUT /cart/items/{productId}` · `DELETE /cart/items/{productId}` · `DELETE /cart`
- **Orders**: `POST /orders/checkout` {shipping details, paymentMethod: CARD|AFTERPAY} + required header `Idempotency-Key` → creates PENDING_PAYMENT order + reserves stock + returns bill · `GET /orders/{publicId}` · `GET /orders?customerId=` · `PUT /orders/{id}/cancel` (releases stock)
- **Payments**: `POST /payments/checkout-session` {orderId, paymentMethod} + required header `Idempotency-Key` → Stripe Checkout Session URL · `POST /webhooks/stripe` (signature-verified)

## Key design decisions
1. **Redis caching (reads)**: `@Cacheable("products")` / `"product"` / `"categories"` with TTL ~10 min; `@CacheEvict`/`@CachePut` on product/inventory writes. Cart stored in Redis hash (TTL 7d) keyed by session/customer, persisted to DB at checkout. Availability checks always read Postgres (never trust cache for stock).
2. **Inventory correctness**: reservation at checkout via atomic conditional `UPDATE inventory SET quantity_reserved = quantity_reserved + :q WHERE product_id=:id AND quantity_on_hand - quantity_reserved >= :q` (0 rows ⇒ `OutOfStockException`), plus `@Version` as a backstop. Add-to-cart does a non-reserving availability check; checkout does the authoritative reservation. A scheduled job expires unpaid orders after 30 min and releases stock.
3. **Transactional payment write**: the webhook handler `PaymentService.handleCheckoutCompleted(event)` is one `@Transactional` method that (a) inserts into `processed_stripe_events` (duplicate ⇒ no-op, idempotent), (b) sets `payments.status`, (c) sets `orders.status = PAID`, (d) converts reserved → sold (`on_hand -= q`, `reserved -= q`) and writes `inventory_movements`. Any failure rolls the whole thing back and Stripe retries. Failure/expiry events release reservations in a similar single transaction. Redis eviction of affected products is registered via `TransactionSynchronization.afterCommit`.
4. **Payment redirect**: frontend calls the BFF `POST /api/payments/checkout-session` (which calls Spring `POST /payments/checkout-session`), receives `{sessionId, url}`, loads Stripe via `loadStripe(publishableKey)` and redirects the browser to Stripe's hosted page; `success_url`/`cancel_url` return to `/payment/success?order=` and `/payment/cancel`. The success page polls `GET /orders/{id}` until status is PAID (the webhook, not the redirect, is the source of truth). Stripe secret/webhook keys come from env vars, never committed.
5. **Price integrity**: server recomputes totals from DB prices; the client total is display-only. Totals = Σ line_total + shipping_fee + tax.
6. **Security baseline**: Spring Security, CORS for the frontend origin, admin-only write endpoints for products/inventory (simple role check; full auth is out of v1 scope but hooks are in place), input validation on all DTOs.
7. **Redux state**: slices `catalogue`, `cart`, `checkout`; RTK Query for client-side server data (pointing at the BFF `/api/*`); cart slice mirrors the server cart; the guest session token lives in an `httpOnly` cookie set by the BFF (not `localStorage`). Stripe webhooks go directly to Spring (`/webhooks/stripe`), not through the BFF.
9. **Payment methods (Card + Afterpay) — no extra library needed**: Afterpay (branded Clearpay in UK/EU) is a native Stripe payment method (`afterpay_clearpay`), so the existing `stripe-java` (backend) and `@stripe/stripe-js` (frontend) cover both options; no separate Afterpay SDK. The checkout page has a payment-method form (radio cards: "Credit / Debit card", "Afterpay") whose selection is sent to the backend, which creates the Checkout Session with `payment_method_types = [card]` or `[afterpay_clearpay]` (and `shipping_address_collection` / prefilled shipping, which Afterpay requires). Constraints handled in code and surfaced in the UI: Afterpay is only offered when currency/shipping country are supported (US, CA, AU, NZ, UK, and Stripe-supported EU markets, configurable in `application.yml`) and when the order total is within Afterpay's min/max limits (configurable; otherwise the option is disabled with an explanatory hint). Afterpay is asynchronous-confirmation, so the webhook-as-source-of-truth design applies to both methods. Requires Afterpay to be enabled in the Stripe Dashboard (test mode works).
10. **Idempotency for Place order / payment API**: the client generates a UUID `Idempotency-Key` when the checkout page loads (kept in the checkout slice, regenerated only after a terminal failure or cart change) and the BFF forwards it. Backend `IdempotencyService` (in `common/`): (a) inserts `idempotency_keys` row `IN_PROGRESS` with a unique PK in its own short transaction — a concurrent duplicate hits the unique violation → `409 Conflict` ("request in progress", retryable); (b) same key + same `request_hash` after completion → returns the stored response verbatim (same order id and same Stripe URL, no second order, reservation or Session); (c) same key + different payload → `422 Unprocessable` ; (d) on success the response is stored in the **same transaction** as the order and payment rows. The same key is passed to Stripe as the `Idempotency-Key` request option (`RequestOptions`) so a retried Session create can't double-create on Stripe's side. The partial unique index on `payments(order_id)` is the DB-level backstop. The UI also disables the "Place order" button while the request is in flight.
8. **SSR + Redis**: three cache layers — Redis in Spring (DB reads), Next fetch cache/ISR (SSR HTML data), Redux (client UI state). Writes evict Redis in Spring and call `revalidateTag` in the BFF.

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

## Testing strategy
**Backend (`backend/src/test`)**
- *Unit*: JUnit 5 + Mockito (`@ExtendWith(MockitoExtension.class)`) + AssertJ for `ProductService`, `CartService`, `InventoryService`, `OrderService`, `PaymentService` (verify with `InOrder`, `ArgumentCaptor`; rollback tested by making a mocked repository throw and asserting the Spring `@Transactional` proxy rolls back in an integration slice).
- *Web slice*: `@WebMvcTest` + MockMvc + `@MockitoBean` for each controller (status codes, validation, ProblemDetail bodies, webhook signature).
- *Repository slice*: `@DataJpaTest` with Testcontainers Postgres (real constraints, conditional update query).
- *Integration*: `@SpringBootTest` + Testcontainers (Postgres + Redis) for cache behaviour, concurrent reservation, and transactional webhook; Stripe is mocked behind a `PaymentGateway` interface (WireMock for HTTP-level).
- *Cucumber-JVM* (`cucumber-spring`, `cucumber-junit-platform-engine`) runs `@backend` scenarios from `/features` against service-layer steps with mocks.
- Coverage gate with JaCoCo (≥ 80% lines on service packages).

**Frontend (`frontend/src`)**
- Jest (`next/jest`) + React Testing Library with `renderWithProviders` (Redux store; `next/navigation` mocked — no React Router); MSW for API. Async server components are tested by awaiting the component function and rendering its result with `backendClient` mocked; `app/api/**/route.ts` handlers are invoked directly with `Request` objects in the `node` environment; `user-event` for interaction; `jest-cucumber` binds `@frontend` scenarios to step files in `__tests__/`.
- Slice unit tests (reducers/selectors), component tests (ProductCard, CartItemRow, ShippingForm validation, PaymentRedirect with `loadStripe` mocked), page-level flows (catalogue → add to cart → checkout → redirect).
- Stripe redirect asserted via mocked `window.location.assign` / `stripe.redirectToCheckout` mock.

## Build order (TDD, each step starts with its `.feature` scenarios and failing tests)
1. Scaffolding: create the two repos, Docker Compose (Postgres/Redis) in the backend repo, `db/schema.sql` + seed + Flyway baseline, Spring Boot + Next.js (App Router)/Tailwind/Jest/RTL skeletons, CI workflow running both test suites.
2. Backend: categories/products CRUD + Redis caching → inventory service.
3. Backend: customers + shipping addresses CRUD → Redis cart service.
4. Backend: checkout/order service (reservation, totals) → Stripe gateway, checkout-session endpoint, transactional webhook, expiry job.
5. Frontend: BFF `backendClient` + route handlers → SSR catalogue/product pages → store + cart → checkout form/bill → payment redirect + success/cancel pages.
6. End-to-end smoke (Playwright, optional) with Stripe test mode and `stripe listen` forwarding webhooks locally; polish, docs, OpenAPI.

## Verification (end-to-end)
- Open `http://localhost:8080/swagger-ui.html` and confirm every endpoint (incl. Idempotency-Key header) is listed and callable.
- `cd planet-m-shop-backend && ./mvnw verify` — unit, slice, Testcontainers integration and Cucumber suites all green; JaCoCo gate passes.
- `cd planet-m-shop-frontend && npm test` — all Jest/RTL/jest-cucumber suites green; `npm run build` (Next production build) and `npm run lint` pass. `curl localhost:3000/products` shows product names in the raw HTML (confirms SSR).
- `docker compose up` then walk through manually: browse catalogue → add item (try exceeding stock to see the error) → checkout form shows the correct total → Pay now redirects to Stripe test checkout (card `4242 4242 4242 4242`) → return to the success page → verify in Postgres that `payments`, `orders`, `inventory` and `inventory_movements` changed together; replay the webhook with `stripe events resend` and confirm no double-decrement; check `redis-cli KEYS 'products*'` shows cache entries that disappear after a product update.

## Open items to confirm before building
- "`/app` directory" is interpreted as Next.js App Router at `frontend/app/` (BFF handlers in `frontend/app/api/`); the Spring Boot API stays a separate service.
- Stripe Checkout (hosted redirect, recommended) vs. embedded Elements — plan assumes hosted redirect as requested.
- Customer authentication (login/JWT) is out of v1 scope — guest checkout + basic admin role only.
- Currency/tax/shipping fee rules (plan assumes a single currency, flat shipping fee, configurable tax rate).
