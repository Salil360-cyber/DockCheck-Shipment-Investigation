-- =====================================================================
-- DockCheck | Step 4: Investigation A - Why are shipments late?
-- Public DataCo dataset (Kaggle). Canceled orders are excluded from late-rate math
-- because they were never delivered (see data check 2.10).
-- =====================================================================

-- A1. The size of the problem
SELECT
    COUNT(*)                                                       AS total_orders,
    COUNT(*) FILTER (WHERE delivery_status = 'Shipping canceled')  AS canceled_orders,
    COUNT(*) FILTER (WHERE delivery_status <> 'Shipping canceled') AS shipped_orders,
    COUNT(*) FILTER (WHERE is_late = 1)                            AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late = 1)
          / COUNT(*) FILTER (WHERE delivery_status <> 'Shipping canceled'), 1) AS late_pct_of_shipped
FROM orders;

-- A2. Hypothesis 1: "It's a geography problem" -> late rate by market
SELECT
    market,
    COUNT(*)                                  AS shipped_orders,
    ROUND(100.0 * AVG(is_late), 1)            AS late_pct
FROM orders
WHERE delivery_status <> 'Shipping canceled'
GROUP BY market
ORDER BY late_pct DESC;

-- A3. Hypothesis 2: "It got worse over time" -> late rate by quarter
SELECT
    TO_CHAR(order_ts, 'YYYY-"Q"Q')            AS order_quarter,
    COUNT(*)                                  AS shipped_orders,
    ROUND(100.0 * AVG(is_late), 1)            AS late_pct
FROM orders
WHERE delivery_status <> 'Shipping canceled'
GROUP BY order_quarter
ORDER BY order_quarter;

-- A4. Hypothesis 3: "It depends on the shipping mode"
SELECT
    shipping_mode,
    COUNT(*)                                  AS shipped_orders,
    ROUND(AVG(days_scheduled), 1)             AS avg_days_promised,
    ROUND(AVG(days_actual), 1)                AS avg_days_actual,
    ROUND(100.0 * AVG(is_late), 1)            AS late_pct
FROM orders
WHERE delivery_status <> 'Shipping canceled'
GROUP BY shipping_mode
ORDER BY late_pct DESC;

-- A5. Deep dive: how many days did each mode ACTUALLY take?
--     Window function: share of each "actual days" value within its mode.
SELECT
    shipping_mode,
    days_scheduled                                  AS days_promised,
    days_actual,
    COUNT(*)                                        AS orders,
    ROUND(100.0 * COUNT(*)
          / SUM(COUNT(*)) OVER (PARTITION BY shipping_mode), 1) AS pct_of_mode
FROM orders
WHERE delivery_status <> 'Shipping canceled'
GROUP BY shipping_mode, days_scheduled, days_actual
ORDER BY shipping_mode, days_actual;

-- A6. How late is "late"? Days beyond the promise, per mode
SELECT
    shipping_mode,
    days_actual - days_scheduled               AS days_over_promise,
    COUNT(*)                                   AS late_orders
FROM orders
WHERE is_late = 1
GROUP BY shipping_mode, days_over_promise
ORDER BY shipping_mode, days_over_promise;

-- A7. What-if: if First Class promised 2 days and Second Class promised
--     4 days, how many of today's late orders would be on time?
WITH revised AS (
    SELECT
        order_id,
        shipping_mode,
        is_late,
        CASE shipping_mode
             WHEN 'First Class'  THEN 2
             WHEN 'Second Class' THEN 4
             ELSE days_scheduled
        END AS new_promise,
        days_actual
    FROM orders
    WHERE delivery_status <> 'Shipping canceled'
)
SELECT
    COUNT(*) FILTER (WHERE is_late = 1)                     AS late_today,
    COUNT(*) FILTER (WHERE days_actual > new_promise)        AS late_with_new_promise,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late = 1) / COUNT(*), 1)              AS late_pct_today,
    ROUND(100.0 * COUNT(*) FILTER (WHERE days_actual > new_promise) / COUNT(*), 1) AS late_pct_new
FROM revised;

-- A8. Canceled orders: genuine cancellations or fraud holds?
SELECT
    order_status,
    COUNT(*)                                          AS canceled_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_canceled
FROM orders
WHERE delivery_status = 'Shipping canceled'
GROUP BY order_status
ORDER BY canceled_orders DESC;
