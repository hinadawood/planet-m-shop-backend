# Planet-M Shop — Backend
Spring Boot 3 / Java 21 / PostgreSQL / Redis / Stripe. See the project plan for the full design.

```bash
cp .env.example .env     # fill in Stripe test keys
docker compose up -d     # postgres + redis (needs Docker Desktop running)
./mvnw spring-boot:run   # Flyway applies db/migrations on startup
```
Swagger UI: http://localhost:8080/swagger-ui.html
