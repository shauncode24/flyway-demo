UPDATE customers
SET email = lower(replace(name, ' ', '.')) || '@example.com'
WHERE email IS NULL;

ALTER TABLE customers ALTER COLUMN email SET NOT NULL;
ALTER TABLE customers ADD CONSTRAINT uq_customers_email UNIQUE (email);