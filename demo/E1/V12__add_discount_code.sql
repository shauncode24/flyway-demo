CREATE TABLE discount_codes (
    id          SERIAL PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    percent_off INT NOT NULL CHECK (percent_off BETWEEN 1 AND 100)
);
