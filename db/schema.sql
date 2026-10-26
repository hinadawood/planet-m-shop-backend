-- Planet-M Shop: full schema (PostgreSQL 16). Kept in sync with db/migrations by SchemaSyncTest.
-- The planetm database itself is created by docker-compose (POSTGRES_DB); apply this file inside it.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE customers (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email         VARCHAR(255) NOT NULL UNIQUE,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    phone         VARCHAR(32),
    password_hash VARCHAR(255),
    is_guest      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE shipping_addresses (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT       NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
    full_name   VARCHAR(200) NOT NULL,
    line1       VARCHAR(255) NOT NULL,
    line2       VARCHAR(255),
    city        VARCHAR(100) NOT NULL,
    state       VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20)  NOT NULL,
    country     CHAR(2)      NOT NULL,
    phone       VARCHAR(32)  NOT NULL,
    is_default  BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_shipping_addresses_customer ON shipping_addresses (customer_id);

CREATE TABLE categories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    slug        VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE products (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku         VARCHAR(64)    NOT NULL UNIQUE,
    name        VARCHAR(255)   NOT NULL,
    description TEXT,
    category_id BIGINT         NOT NULL REFERENCES categories (id),
    price       NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    currency    CHAR(3)        NOT NULL DEFAULT 'USD',
    image_url   VARCHAR(512),
    material    VARCHAR(100),
    size        VARCHAR(50),
    color       VARCHAR(50),
    is_active   BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX idx_products_category_active ON products (category_id, is_active);

CREATE TABLE inventory (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id        BIGINT      NOT NULL UNIQUE REFERENCES products (id),
    quantity_on_hand  INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level     INTEGER     NOT NULL DEFAULT 0,
    version           BIGINT      NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_inventory_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand)
);

CREATE TABLE carts (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   BIGINT REFERENCES customers (id),
    session_token VARCHAR(64) UNIQUE,
    status        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CHECKED_OUT', 'ABANDONED')),
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE cart_items (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id             BIGINT         NOT NULL REFERENCES carts (id) ON DELETE CASCADE,
    product_id          BIGINT         NOT NULL REFERENCES products (id),
    quantity            INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price_snapshot NUMERIC(12, 2) NOT NULL,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_cart_items_cart_product UNIQUE (cart_id, product_id)
);
CREATE INDEX idx_cart_items_cart ON cart_items (cart_id);

CREATE TABLE orders (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    public_id              UUID           NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    customer_id            BIGINT         NOT NULL REFERENCES customers (id),
    shipping_address_id    BIGINT         NOT NULL REFERENCES shipping_addresses (id),
    status                 VARCHAR(20)    NOT NULL DEFAULT 'PENDING_PAYMENT'
        CHECK (status IN ('PENDING_PAYMENT', 'PAID', 'PAYMENT_FAILED', 'CANCELLED', 'EXPIRED', 'SHIPPED', 'DELIVERED')),
    subtotal               NUMERIC(12, 2) NOT NULL CHECK (subtotal >= 0),
    shipping_fee           NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    tax                    NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (tax >= 0),
    total                  NUMERIC(12, 2) NOT NULL CHECK (total >= 0),
    currency               CHAR(3)        NOT NULL DEFAULT 'USD',
    placed_at              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    reservation_expires_at TIMESTAMPTZ,
    created_at             TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_customer_status ON orders (customer_id, status);

CREATE TABLE order_items (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT         NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    product_id   BIGINT         NOT NULL REFERENCES products (id),
    sku          VARCHAR(64)    NOT NULL,
    product_name VARCHAR(255)   NOT NULL,
    unit_price   NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    quantity     INTEGER        NOT NULL CHECK (quantity > 0),
    line_total   NUMERIC(12, 2) NOT NULL CHECK (line_total >= 0),
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX idx_order_items_order ON order_items (order_id);

CREATE TABLE payments (
    id                        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                  BIGINT         NOT NULL REFERENCES orders (id),
    provider                  VARCHAR(20)    NOT NULL DEFAULT 'STRIPE',
    payment_method            VARCHAR(20)    NOT NULL CHECK (payment_method IN ('CARD', 'AFTERPAY')),
    stripe_checkout_session_id VARCHAR(255)  UNIQUE,
    stripe_payment_intent_id  VARCHAR(255),
    amount                    NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    currency                  CHAR(3)        NOT NULL,
    status                    VARCHAR(20)    NOT NULL DEFAULT 'INITIATED'
        CHECK (status IN ('INITIATED', 'SUCCEEDED', 'FAILED', 'EXPIRED', 'REFUNDED')),
    failure_reason            VARCHAR(500),
    created_at                TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_order ON payments (order_id);
CREATE UNIQUE INDEX uq_payments_one_live_per_order ON payments (order_id) WHERE status IN ('INITIATED', 'SUCCEEDED');

CREATE TABLE processed_stripe_events (
    stripe_event_id VARCHAR(255) PRIMARY KEY,
    type            VARCHAR(100) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE idempotency_keys (
    idempotency_key VARCHAR(64)  PRIMARY KEY,
    scope           VARCHAR(30)  NOT NULL CHECK (scope IN ('PLACE_ORDER', 'CREATE_PAYMENT_SESSION')),
    owner_ref       VARCHAR(64),
    request_hash    CHAR(64)     NOT NULL,
    status          VARCHAR(20)  NOT NULL CHECK (status IN ('IN_PROGRESS', 'COMPLETED')),
    response_status INTEGER,
    response_body   JSONB,
    order_id        BIGINT REFERENCES orders (id),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ  NOT NULL DEFAULT now() + INTERVAL '24 hours'
);
CREATE INDEX idx_idempotency_keys_expires ON idempotency_keys (expires_at);

CREATE TABLE inventory_movements (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT      NOT NULL REFERENCES products (id),
    order_id   BIGINT REFERENCES orders (id),
    delta      INTEGER     NOT NULL,
    reason     VARCHAR(20) NOT NULL CHECK (reason IN ('RESERVE', 'RELEASE', 'COMMIT', 'RESTOCK')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_inventory_movements_product ON inventory_movements (product_id);

-- updated_at triggers
CREATE TRIGGER trg_customers_updated BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_shipping_addresses_updated BEFORE UPDATE ON shipping_addresses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_categories_updated BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_inventory_updated BEFORE UPDATE ON inventory FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_carts_updated BEFORE UPDATE ON carts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_cart_items_updated BEFORE UPDATE ON cart_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_order_items_updated BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_payments_updated BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
