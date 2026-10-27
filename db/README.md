# Database notes (Flyway & schema)

## Who creates what
| Step | Creates | How |
|---|---|---|
| `docker compose up -d` | An **empty** `planetm` database and `planetm` user | `postgres:16` image, from `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` in `docker-compose.yml` |
| Starting the Spring Boot backend | All Postgres **tables**, the restricted `planetm_app` role and, in the dev profile only, the **seed data** | Flyway, embedded in the app, applies `db/migrations/` (plus `db/seed-dev/` in the dev profile) |
| `docker compose up -d` (the `cassandra-init` job) | The **Cassandra** keyspace `planetm` and its three tables | Runs `db/cassandra/schema.cql` once Cassandra is healthy — see "Cassandra" below |

- Docker Compose does **not** run `schema.sql`. It is not mounted into the container.
- No Flyway container or image is used.
- If you start only the containers and never the backend, the database stays empty.

## Files in this folder
- `schema.sql` — readable full DDL for every table. A reference, and the file `SchemaSyncTest` compares against the migrations. Can be applied by hand: `psql -U planetm -d planetm -f db/schema.sql` (create the database first with `createdb planetm` if you are not using docker-compose).
- `seed.sql` — sample categories, products and stock (same content as `seed-dev/V2__seed.sql`).
- `migrations/` — what Flyway runs in every environment (`V1__baseline.sql` = tables, `V3__app_role_and_privileges.sql` = restricted app role and grants).
- `seed-dev/` — `V2__seed.sql`, sample data that Flyway loads **only in the dev profile** (`application-dev.yml`, the local default). Production (`SPRING_PROFILES_ACTIVE=prod`) does not load it, so production starts with no categories or products; an admin creates them through the API. Flyway allows the gap in version numbers (V1, V3) in production.
- `cassandra/schema.cql` — order-history keyspace and tables (see below).
- `ops/` — frequently-run SQL: `procedures/` (repeatable `R__*.sql`), `maintenance/` (`purge_published_outbox.sql`, `low_stock_report.sql`), `backup/`. Maintenance scripts run as the owner role (`planetm`), not the app role.

## Cassandra (applied separately from Postgres)
Order history and the transaction log live in Cassandra, not Postgres. **Flyway does not manage it.** Its schema, `db/cassandra/schema.cql`, is applied by the `cassandra-init` job in `docker-compose.yml`, which waits for the `cassandra` container to be healthy and then runs `cqlsh -f schema.cql`. Every statement uses `IF NOT EXISTS`, so re-running the job is safe. To apply it by hand: `docker compose up cassandra-init`. The `SimpleStrategy` / replication factor 1 setting in the file is for development only; use `NetworkTopologyStrategy` in production. Cassandra data is filled by the backend's outbox publisher from the Postgres `outbox_events` table; losing the Cassandra volume loses history copies but not orders.

## Roles and privileges
Flyway connects as the owner role `planetm`; the application connects as `planetm_app`, created by `V3__app_role_and_privileges.sql`. `planetm_app` cannot create or drop tables, cannot UPDATE/DELETE/TRUNCATE the append-only tables (`payment_events`, `inventory_movements`, `processed_stripe_events`), and has `lock_timeout`, `statement_timeout` and `idle_in_transaction_session_timeout` set. **Every migration that adds a table must include its own `GRANT` lines for `planetm_app`.** `schema.sql` holds tables only; privileges live in `V3` and are not part of the `SchemaSyncTest` comparison.

## How Flyway behaves
- **Restart of the backend:** Flyway reads its `flyway_schema_history` table and skips every migration already applied. Tables and data are untouched, and seed data is not inserted twice.
- **New change:** add a new file with the next version, e.g. `V4__add_column.sql`. Only that file runs on the next start.
- **Never edit an applied migration** (`V1`, `V2`, `V3`, ...). Flyway stores a checksum for each; editing one makes the next startup fail with a checksum mismatch. Put the change in a new `V<n>` file instead.
- **Repeatable migrations** (`R__*.sql`, e.g. stored procedures) are the exception: they re-run whenever their content changes.
- **Tables are recreated only if the database is gone**, e.g. after `docker compose down -v` (deletes the `pgdata` volume). Plain `docker compose down` keeps the data.

## Keeping `schema.sql` and migrations in sync
When a new `V<n>` migration changes the schema, update `schema.sql` to match. `SchemaSyncTest` fails the build if the schema produced by the migrations differs from the one produced by `schema.sql`.

## Not needed in schema.sql
`CREATE DATABASE` is deliberately omitted: docker-compose creates `planetm`, and Flyway cannot create a database from inside a migration.
