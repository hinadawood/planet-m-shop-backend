-- Planet-M Shop order history and transaction log (Cassandra 5).
-- Postgres is the system of record; OutboxPublisher upserts here (idempotent, same primary keys).
CREATE KEYSPACE IF NOT EXISTS planetm
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};  -- dev only; use NetworkTopologyStrategy in production

CREATE TABLE IF NOT EXISTS planetm.orders_by_customer (
    customer_id    bigint,
    placed_at      timestamp,
    order_id       uuid,
    status         text,
    total          decimal,
    currency       text,
    payment_method text,
    item_count     int,
    PRIMARY KEY ((customer_id), placed_at, order_id)
) WITH CLUSTERING ORDER BY (placed_at DESC, order_id ASC);

CREATE TABLE IF NOT EXISTS planetm.order_by_id (
    order_id         uuid PRIMARY KEY,
    customer_id      bigint,
    status           text,
    placed_at        timestamp,
    subtotal         decimal,
    shipping_fee     decimal,
    tax              decimal,
    total            decimal,
    currency         text,
    payment_method   text,
    items_json       text,
    shipping_json    text
);

CREATE TABLE IF NOT EXISTS planetm.order_events_by_order (
    order_id    uuid,
    event_time  timeuuid,
    event_type  text,
    payload     text,
    PRIMARY KEY ((order_id), event_time)
) WITH CLUSTERING ORDER BY (event_time ASC);
