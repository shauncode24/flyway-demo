-- A "legacy" database that was built by hand, never under Flyway control.
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    email VARCHAR(150) NOT NULL UNIQUE
);
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock INT NOT NULL DEFAULT 0
);
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(id),
    status VARCHAR(20) NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW','PAID','SHIPPED','CANCELLED')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INT NOT NULL REFERENCES products(id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL
);
INSERT INTO customers (name, email) VALUES ('Legacy User', 'legacy.user@example.com');
INSERT INTO products (name, price, stock) VALUES ('Legacy Item', 999.00, 5);
INSERT INTO orders (customer_id, status) VALUES (1, 'PAID');
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (1, 1, 1, 999.00);
