-- =====================================================================
-- DockCheck | Step 2: Data quality checks (run BEFORE cleaning)
-- An investigator checks the evidence before trusting it.
-- Run each query one by one and note the result.
-- =====================================================================

-- 2.1 Row counts: did everything load?
SELECT 'stg_dataco' AS table_name, COUNT(*) AS row_count FROM stg_dataco
UNION ALL
SELECT 'stg_receiving_log', COUNT(*) FROM stg_receiving_log;

-- 2.2 Duplicate order items (each order item should appear once)
SELECT order_item_id, COUNT(*) AS times_seen
FROM stg_dataco
GROUP BY order_item_id
HAVING COUNT(*) > 1;

-- 2.3 Empty / useless columns
SELECT
    COUNT(*) FILTER (WHERE product_description IS NULL OR product_description = '') AS empty_product_description,
    COUNT(*) FILTER (WHERE order_zipcode IS NULL OR order_zipcode = '')             AS empty_order_zipcode,
    COUNT(DISTINCT customer_email)    AS distinct_emails,     -- masked as XXXXXXXXX
    COUNT(DISTINCT customer_password) AS distinct_passwords,  -- masked as XXXXXXXXX
    COUNT(DISTINCT product_status)    AS distinct_product_status
FROM stg_dataco;

-- 2.4 Same category name used for two different category IDs
SELECT category_name,
       COUNT(DISTINCT category_id)              AS id_count,
       STRING_AGG(DISTINCT category_id, ', ')   AS category_ids,
       STRING_AGG(DISTINCT department_name, ', ') AS departments
FROM stg_dataco
GROUP BY category_name
HAVING COUNT(DISTINCT category_id) > 1;

-- 2.5 Look at what is actually inside those "Electronics" categories
SELECT DISTINCT category_id, department_name, product_name
FROM stg_dataco
WHERE category_name = 'Electronics'
ORDER BY category_id, product_name;

-- 2.6 Shifted address columns (city holds a state code, state holds a zipcode)
SELECT DISTINCT customer_id, customer_city, customer_state, customer_zipcode
FROM stg_dataco
WHERE customer_state ~ '^[0-9]+$';

-- 2.7 Product names with extra spaces at the end
SELECT COUNT(*) AS rows_with_trailing_space
FROM stg_dataco
WHERE product_name <> TRIM(product_name);

-- 2.8 Country names stored in Spanish
SELECT customer_country, COUNT(*) AS rows_
FROM stg_dataco
GROUP BY customer_country;

-- 2.9 Does the "late" flag agree with the day columns?
SELECT late_delivery_risk,
       COUNT(*) FILTER (WHERE days_for_shipping_real::INT >  days_for_shipment_scheduled::INT) AS real_more_than_scheduled,
       COUNT(*) FILTER (WHERE days_for_shipping_real::INT <= days_for_shipment_scheduled::INT) AS real_within_scheduled
FROM stg_dataco
GROUP BY late_delivery_risk;

-- 2.10 Who are the rows that took longer than scheduled but are NOT flagged late?
SELECT delivery_status, COUNT(*) AS rows_
FROM stg_dataco
WHERE late_delivery_risk = '0'
  AND days_for_shipping_real::INT > days_for_shipment_scheduled::INT
GROUP BY delivery_status;
-- Answer: all are "Shipping canceled". Canceled orders still carry shipping
-- days, so they must be EXCLUDED when we calculate the late-delivery rate.

-- 2.11 Does every market cover the same dates?
SELECT market,
       MIN(TO_TIMESTAMP(order_date, 'MM/DD/YYYY HH24:MI'))::DATE AS first_order,
       MAX(TO_TIMESTAMP(order_date, 'MM/DD/YYYY HH24:MI'))::DATE AS last_order,
       COUNT(DISTINCT order_id)                                   AS orders
FROM stg_dataco
GROUP BY market
ORDER BY last_order;
-- Answer: NO. Each market covers a different window (USCA only Apr 2016 -
-- Jan 2017; after Nov 2017 only Pacific Asia). So never read a month-by-month
-- trend as "the business got better/worse" without checking which markets
-- are in that month.
