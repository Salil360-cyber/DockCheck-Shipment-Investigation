-- =====================================================================
-- DockCheck | Step 1: Staging tables
-- Raw data is loaded exactly as it comes (every column as TEXT).
-- We clean and convert types later, in step 3. This way the import
-- never fails because of one bad value.
-- =====================================================================

DROP TABLE IF EXISTS stg_dataco;

CREATE TABLE stg_dataco (
    payment_type                TEXT,  -- "Type"
    days_for_shipping_real      TEXT,
    days_for_shipment_scheduled TEXT,
    benefit_per_order           TEXT,
    sales_per_customer          TEXT,
    delivery_status             TEXT,
    late_delivery_risk          TEXT,
    category_id                 TEXT,
    category_name               TEXT,
    customer_city               TEXT,
    customer_country            TEXT,
    customer_email              TEXT,
    customer_fname              TEXT,
    customer_id                 TEXT,
    customer_lname              TEXT,
    customer_password           TEXT,
    customer_segment            TEXT,
    customer_state              TEXT,
    customer_street             TEXT,
    customer_zipcode            TEXT,
    department_id               TEXT,
    department_name             TEXT,
    latitude                    TEXT,
    longitude                   TEXT,
    market                      TEXT,
    order_city                  TEXT,
    order_country               TEXT,
    order_customer_id           TEXT,
    order_date                  TEXT,
    order_id                    TEXT,
    order_item_cardprod_id      TEXT,
    order_item_discount         TEXT,
    order_item_discount_rate    TEXT,
    order_item_id               TEXT,
    order_item_product_price    TEXT,
    order_item_profit_ratio     TEXT,
    order_item_quantity         TEXT,
    sales                       TEXT,
    order_item_total            TEXT,
    order_profit_per_order      TEXT,
    order_region                TEXT,
    order_state                 TEXT,
    order_status                TEXT,
    order_zipcode               TEXT,
    product_card_id             TEXT,
    product_category_id         TEXT,
    product_description         TEXT,
    product_image               TEXT,
    product_name                TEXT,
    product_price               TEXT,
    product_status              TEXT,
    shipping_date               TEXT,
    shipping_mode               TEXT
);

DROP TABLE IF EXISTS stg_receiving_log;

CREATE TABLE stg_receiving_log (
    receipt_id     TEXT,
    order_item_id  TEXT,
    fc_code        TEXT,
    received_date  TEXT,
    shipped_qty    TEXT,
    received_qty   TEXT,
    damaged_qty    TEXT,
    receipt_status TEXT
);
