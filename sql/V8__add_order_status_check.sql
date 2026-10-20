ALTER TABLE orders
    ADD CONSTRAINT chk_orders_status
    CHECK (status IN ('NEW', 'PAID', 'SHIPPED', 'CANCELLED'));