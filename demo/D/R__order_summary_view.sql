-- Repeatable: re-applied by Flyway whenever this file's content changes
CREATE OR REPLACE VIEW order_summary AS
SELECT o.id AS order_id,
       c.name AS customer,
       o.status,
       SUM(oi.quantity * oi.unit_price) AS total,
       SUM(oi.quantity) AS item_count
FROM orders o
JOIN customers c    ON c.id = o.customer_id
JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, c.name, o.status;
