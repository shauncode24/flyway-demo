INSERT INTO customers (name, email) VALUES
    ('Asha Rao',    'asha.rao@example.com'),
    ('Rohan Mehta', 'rohan.mehta@example.com'),
    ('Priya Nair',  'priya.nair@example.com');

INSERT INTO products (name, price, stock) VALUES
    ('Laptop Stand',        1499.00, 40),
    ('USB-C Hub',           2299.00, 25),
    ('Mechanical Keyboard', 4999.00, 15);

INSERT INTO orders (customer_id, status) VALUES
    (1, 'PAID'), (2, 'NEW'), (1, 'SHIPPED');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 1, 1499.00),
    (1, 2, 2, 2299.00),
    (2, 3, 1, 4999.00),
    (3, 2, 1, 2299.00);