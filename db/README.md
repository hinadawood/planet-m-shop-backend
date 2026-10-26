# Database notes (Flyway & schema)

## Who creates what
| Step | Creates | How |
|---|---|---|
| `docker compose up -d` | An **empty** `planetm` database and `planetm` user | `postgres:16` image, from `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` in `docker-compose.yml` |
| Starting the Spring Boot backend | All **tables** and the **seed data** | Flyway, embedded in the app, applies `db/migrations/` |

- Docker Compose does **not** run `schema.sql`. It is not mounted into the container.
- No Flyway container or image is used.
- If you start only the containers and never the backend, the database stays empty.

## Files in this folder
- `schema.sql` — readable full DDL for every table. A reference, and the file `SchemaSyncTest` compares against the migrations. Can be applied by hand: `psql -U planetm -d planetm -f db/schema.sql` (create the database first with `createdb planetm` if you are not using docker-compose).
- `seed.sql` — sample categories, products and stock (same content as `V2__seed.sql`).
- `migrations/` — what Flyway actually runs (`V1__baseline.sql` = schema, `V2__seed.sql` = seed data).
- `ops/` — frequently-run SQL: `procedures/` (repeatable `R__*.sql`), `maintenance/`, `backup/`.

## How Flyway behaves
- **Restart of the backend:** Flyway reads its `flyway_schema_history` table and skips every migration already applied. Tables and data are untouched, and seed data is not inserted twice.
- **New change:** add a new file with the next version, e.g. `V3__add_column.sql`. Only that file runs on the next start.
- **Never edit an applied migration** (`V1`, `V2`, ...). Flyway stores a checksum for each; editing one makes the next startup fail with a checksum mismatch. Put the change in a new `V<n>` file instead.
- **Repeatable migrations** (`R__*.sql`, e.g. stored procedures) are the exception: they re-run whenever their content changes.
- **Tables are recreated only if the database is gone**, e.g. after `docker compose down -v` (deletes the `pgdata` volume). Plain `docker compose down` keeps the data.

## Keeping `schema.sql` and migrations in sync
When a new `V<n>` migration changes the schema, update `schema.sql` to match. `SchemaSyncTest` fails the build if the schema produced by the migrations differs from the one produced by `schema.sql`.

## Not needed in schema.sql
`CREATE DATABASE` is deliberately omitted: docker-compose creates `planetm`, and Flyway cannot create a database from inside a migration.
