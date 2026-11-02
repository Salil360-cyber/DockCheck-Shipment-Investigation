-- =====================================================================
-- DockCheck | Step 3: Clean the data and build the final tables
-- One flat 53-column file  ->  6 clean, linked tables.
-- Run the whole file at once (F5 in pgAdmin Query Tool).
-- =====================================================================

DROP TABLE IF EXISTS fc_receiving_log, order_items, orders, fulfillment_centres, products, customers CASCADE;

-- ---------------------------------------------------------------------
-- 3.1 CUSTOMERS
-- Fixes: Spanish country names, 3 customers with shifted address
-- columns, zipcodes stored like "725.0" (should be "00725").
-- Removed: email and password (masked, no value).
-- ---------------------------------------------------------------------
CREATE TABLE customers AS
SELECT DISTINCT
    customer_id::INT                                   AS customer_id,
    TRIM(customer_fname)                               AS first_name,
    NULLIF(TRIM(customer_lname), '')                   AS last_name,
    customer_segment                                   AS segment,
    CASE WHEN customer_state ~ '^[0-9]+$' THEN NULL
         ELSE customer_city END                        AS city,
    CASE WHEN customer_state ~ '^[0-9]+$' THEN customer_city
         ELSE customer_state END                       AS state,
    CASE customer_country
         WHEN 'EE. UU.' THEN 'United States'
         ELSE customer_country END                     AS country,
    CASE WHEN customer_state ~ '^[0-9]+$' THEN LPAD(customer_state, 5, '0')
         ELSE LPAD(SPLIT_PART(customer_zipcode, '.', 1), 5, '0') END AS zipcode
FROM stg_dataco;

ALTER TABLE customers ADD PRIMARY KEY (customer_id);

-- ---------------------------------------------------------------------
-- 3.2 PRODUCTS
-- Fixes: trailing spaces in product and department names
-- (e.g. "Health and Beauty ").
-- Flag: the two "Electronics" categories (13, 37) hold footwear and
-- golf products, so that label cannot be trusted.
-- Removed: product_description (100% empty), product_status (always 0).
-- ---------------------------------------------------------------------
CREATE TABLE products AS
SELECT DISTINCT
    product_card_id::INT                    AS product_id,
    TRIM(product_name)                      AS product_name,
    category_id::INT                        AS category_id,
    category_name,
    department_id::INT                      AS department_id,
    TRIM(department_name)                   AS department_name,
    ROUND(product_price::NUMERIC, 2)        AS unit_price,
    (category_name = 'Electronics')         AS category_label_suspect
FROM stg_dataco;

ALTER TABLE products ADD PRIMARY KEY (product_id);

-- ---------------------------------------------------------------------
-- 3.3 ORDERS (one row per order, includes shipping details)
-- Dates converted from text like "1/31/2018 22:56" to real timestamps.
-- ---------------------------------------------------------------------
CREATE TABLE orders AS
SELECT DISTINCT
    order_id::INT                                          AS order_id,
    order_customer_id::INT                                 AS customer_id,
    TO_TIMESTAMP(order_date,    'MM/DD/YYYY HH24:MI')::TIMESTAMP AS order_ts,
    TO_TIMESTAMP(shipping_date, 'MM/DD/YYYY HH24:MI')::TIMESTAMP AS ship_ts,
    order_status,
    payment_type,
    market,
    order_region,
    order_country,
    order_city,
    shipping_mode,
    days_for_shipment_scheduled::INT                       AS days_scheduled,
    days_for_shipping_real::INT                            AS days_actual,
    delivery_status,
    late_delivery_risk::INT                                AS is_late
FROM stg_dataco;

ALTER TABLE orders ADD PRIMARY KEY (order_id);
ALTER TABLE orders ADD FOREIGN KEY (customer_id) REFERENCES customers (customer_id);

-- ---------------------------------------------------------------------
-- 3.4 ORDER ITEMS (one row per product line in an order)
-- ---------------------------------------------------------------------
CREATE TABLE order_items AS
SELECT
    order_item_id::INT                               AS order_item_id,
    order_id::INT                                    AS order_id,
    product_card_id::INT                             AS product_id,
    order_item_quantity::INT                         AS quantity,
    ROUND(order_item_product_price::NUMERIC, 2)      AS unit_price,
    ROUND(order_item_discount::NUMERIC, 2)           AS discount,
    ROUND(order_item_total::NUMERIC, 2)              AS item_total,
    ROUND(order_profit_per_order::NUMERIC, 2)        AS item_profit
FROM stg_dataco;

ALTER TABLE order_items ADD PRIMARY KEY (order_item_id);
ALTER TABLE order_items ADD FOREIGN KEY (order_id)   REFERENCES orders (order_id);
ALTER TABLE order_items ADD FOREIGN KEY (product_id) REFERENCES products (product_id);

-- ---------------------------------------------------------------------
-- 3.5 FULFILLMENT CENTRES (simulated: one FC serves each market)
-- ---------------------------------------------------------------------
CREATE TABLE fulfillment_centres (
    fc_code TEXT PRIMARY KEY,
    fc_name TEXT,
    market  TEXT
);

INSERT INTO fulfillment_centres VALUES
    ('FC-01', 'North America Hub', 'USCA'),
    ('FC-02', 'Latin America Hub', 'LATAM'),
    ('FC-03', 'Europe Hub',        'Europe'),
    ('FC-04', 'Asia Pacific Hub',  'Pacific Asia'),
    ('FC-05', 'Africa Hub',        'Africa');

-- ---------------------------------------------------------------------
-- 3.6 FC RECEIVING LOG (SIMULATED: shipped vs received units)
-- ---------------------------------------------------------------------
CREATE TABLE fc_receiving_log AS
SELECT
    receipt_id::INT      AS receipt_id,
    order_item_id::INT   AS order_item_id,
    fc_code,
    received_date::DATE  AS received_date,
    shipped_qty::INT     AS shipped_qty,
    received_qty::INT    AS received_qty,
    damaged_qty::INT     AS damaged_qty,
    receipt_status
FROM stg_receiving_log;

ALTER TABLE fc_receiving_log ADD PRIMARY KEY (receipt_id);
ALTER TABLE fc_receiving_log ADD FOREIGN KEY (order_item_id) REFERENCES order_items (order_item_id);
ALTER TABLE fc_receiving_log ADD FOREIGN KEY (fc_code)       REFERENCES fulfillment_centres (fc_code);

-- ---------------------------------------------------------------------
-- 3.7 Indexes on the columns we filter and join on most
-- ---------------------------------------------------------------------
CREATE INDEX idx_items_order    ON order_items (order_id);
CREATE INDEX idx_orders_mode    ON orders (shipping_mode);
CREATE INDEX idx_receiving_item ON fc_receiving_log (order_item_id);
CREATE INDEX idx_receiving_fc   ON fc_receiving_log (fc_code, received_date);

-- ---------------------------------------------------------------------
-- 3.8 Final check: row counts of the clean tables
-- ---------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products',            COUNT(*) FROM products
UNION ALL SELECT 'orders',              COUNT(*) FROM orders
UNION ALL SELECT 'order_items',         COUNT(*) FROM order_items
UNION ALL SELECT 'fulfillment_centres', COUNT(*) FROM fulfillment_centres
UNION ALL SELECT 'fc_receiving_log',    COUNT(*) FROM fc_receiving_log;
