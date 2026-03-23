CREATE TABLE orders (
    id             BIGSERIAL PRIMARY KEY,
    order_number   VARCHAR(50)    NOT NULL UNIQUE,
    customer_name  VARCHAR(100)   NOT NULL,
    status         VARCHAR(20)    NOT NULL DEFAULT 'PENDING',
    total_amount   DECIMAL(12,2),
    created_by     VARCHAR(50)    NOT NULL,
    source         VARCHAR(20)    NOT NULL DEFAULT 'INTERNAL',
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_order_number ON orders(order_number);
CREATE INDEX idx_orders_source ON orders(source);
CREATE INDEX idx_orders_created_by ON orders(created_by);
