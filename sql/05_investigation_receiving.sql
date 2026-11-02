-- =====================================================================
-- DockCheck | Step 5: Investigation B - Units shipped vs units received
-- Uses the SIMULATED fc_receiving_log (see scripts/generate_receiving_log.py).
-- These queries show the investigation METHOD. The patterns they find (FC-03
-- spike, multi-unit shortages, late = more shortages, Golf/Fitness damage)
-- were PLANTED by the generator's documented rules, to test that the queries
-- catch them. They are not discoveries about a real FC.
-- =====================================================================

-- B1. Overall: how many units went missing, extra or damaged?
SELECT
    receipt_status,
    COUNT(*)                                            AS receipts,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_receipts,
    SUM(shipped_qty)                                    AS units_shipped,
    SUM(received_qty)                                   AS units_received,
    SUM(shipped_qty - received_qty)                     AS units_missing,
    SUM(damaged_qty)                                    AS units_damaged
FROM fc_receiving_log
GROUP BY receipt_status
ORDER BY receipts DESC;

-- B2. Which fulfillment centre has the highest shortage rate?
SELECT
    r.fc_code,
    f.fc_name,
    COUNT(*)                                                            AS receipts,
    COUNT(*) FILTER (WHERE r.receipt_status = 'SHORT')                  AS short_receipts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.receipt_status = 'SHORT') / COUNT(*), 2) AS short_pct,
    SUM(r.shipped_qty - r.received_qty) FILTER (WHERE r.receipt_status = 'SHORT')   AS units_missing
FROM fc_receiving_log r
JOIN fulfillment_centres f ON f.fc_code = r.fc_code
GROUP BY r.fc_code, f.fc_name
ORDER BY short_pct DESC;

-- B3. When did it happen? Monthly shortage rate at FC-03 (highest in B2),
--     with the change from the previous month (LAG window function).
--     Note: Europe has no data Feb-May 2017, so the June row is compared
--     with January.
WITH monthly AS (
    SELECT
        fc_code,
        DATE_TRUNC('month', received_date)::DATE AS month,
        COUNT(*)                                 AS receipts,
        ROUND(100.0 * COUNT(*) FILTER (WHERE receipt_status = 'SHORT') / COUNT(*), 2) AS short_pct
    FROM fc_receiving_log
    GROUP BY fc_code, month
)
SELECT
    fc_code,
    month,
    receipts,
    short_pct,
    short_pct - LAG(short_pct) OVER (PARTITION BY fc_code ORDER BY month) AS change_vs_last_month
FROM monthly
WHERE fc_code = 'FC-03'
  AND month >= '2017-01-01'
ORDER BY month;

-- B4. Rank every FC-month by shortage rate: the top 5 are the hotspots
WITH monthly AS (
    SELECT
        fc_code,
        DATE_TRUNC('month', received_date)::DATE AS month,
        COUNT(*) AS receipts,
        ROUND(100.0 * COUNT(*) FILTER (WHERE receipt_status = 'SHORT') / COUNT(*), 2) AS short_pct
    FROM fc_receiving_log
    GROUP BY fc_code, month
    HAVING COUNT(*) >= 100          -- ignore tiny months
)
SELECT *
FROM (
    SELECT monthly.*,
           DENSE_RANK() OVER (ORDER BY short_pct DESC) AS hotspot_rank
    FROM monthly
) ranked
WHERE hotspot_rank <= 5
ORDER BY hotspot_rank;

-- B5. Drill down inside the hotspot (FC-03, Oct-Nov 2017; Europe data ends
--     10 Nov 2017) vs the same FC the rest of the time: worse for multi-unit items?
SELECT
    CASE WHEN received_date BETWEEN '2017-10-01' AND '2017-11-30'
         THEN 'Oct-Nov 2017' ELSE 'All other months' END     AS period,
    CASE WHEN shipped_qty >= 4 THEN '4-5 units' ELSE '1-3 units' END AS item_size,
    COUNT(*)                                                 AS receipts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE receipt_status = 'SHORT') / COUNT(*), 2) AS short_pct
FROM fc_receiving_log
WHERE fc_code = 'FC-03'
GROUP BY period, item_size
ORDER BY period DESC, item_size;

-- B6. Was the hotspot a volume problem? Receipts handled per month at FC-03
--     (note: Europe data stops on 10 Nov 2017, so November is a part-month,
--     and the October drop is the dataset thinning out, not operations)
SELECT
    DATE_TRUNC('month', received_date)::DATE AS month,
    COUNT(*)                                 AS receipts
FROM fc_receiving_log
WHERE fc_code = 'FC-03'
  AND received_date BETWEEN '2017-06-01' AND '2018-01-31'
GROUP BY month
ORDER BY month;

-- B7. Do late shipments arrive short more often? (joins real + simulated)
SELECT
    CASE WHEN o.is_late = 1 THEN 'Late' ELSE 'On time / early' END AS delivery,
    COUNT(*)                                                      AS receipts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.receipt_status = 'SHORT') / COUNT(*), 2) AS short_pct
FROM fc_receiving_log r
JOIN order_items oi ON oi.order_item_id = r.order_item_id
JOIN orders o       ON o.order_id       = oi.order_id
GROUP BY delivery;

-- B8. Damage by department: which products arrive damaged?
SELECT
    p.department_name,
    COUNT(*)                                                       AS receipts,
    COUNT(*) FILTER (WHERE r.receipt_status = 'DAMAGED')           AS damaged_receipts,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.receipt_status = 'DAMAGED') / COUNT(*), 2) AS damaged_pct
FROM fc_receiving_log r
JOIN order_items oi ON oi.order_item_id = r.order_item_id
JOIN products p     ON p.product_id     = oi.product_id
GROUP BY p.department_name
HAVING COUNT(*) >= 300
ORDER BY damaged_pct DESC;

-- B9. The case list: a view the team can work from every day.
--     One row per problem receipt, with everything needed to investigate it.
CREATE OR REPLACE VIEW v_discrepancy_cases AS
SELECT
    r.receipt_id,
    r.fc_code,
    r.received_date,
    o.order_id,
    r.order_item_id,
    p.product_name,
    p.department_name,
    o.shipping_mode,
    o.is_late,
    r.shipped_qty,
    r.received_qty,
    r.damaged_qty,
    r.receipt_status,
    CASE
        WHEN r.receipt_status = 'SHORT'   THEN (r.shipped_qty - r.received_qty) * oi.unit_price
        WHEN r.receipt_status = 'DAMAGED' THEN r.damaged_qty * oi.unit_price
        ELSE 0
    END AS value_at_risk,
    CASE
        WHEN r.receipt_status = 'SHORT' AND r.received_qty = 0 THEN 'P1 - nothing received'
        WHEN r.receipt_status = 'SHORT'                        THEN 'P2 - partial shortage'
        WHEN r.receipt_status = 'DAMAGED'                      THEN 'P3 - damaged units'
        ELSE 'P4 - overage, verify count'
    END AS priority
FROM fc_receiving_log r
JOIN order_items oi ON oi.order_item_id = r.order_item_id
JOIN orders o       ON o.order_id       = oi.order_id
JOIN products p     ON p.product_id     = oi.product_id
WHERE r.receipt_status <> 'MATCHED';

-- B10. Use the case list: cases and money at risk by priority
SELECT
    priority,
    COUNT(*)                     AS cases,
    ROUND(SUM(value_at_risk), 0) AS value_at_risk_usd
FROM v_discrepancy_cases
GROUP BY priority
ORDER BY priority;

-- B11. Top 10 highest-value cases to work first
SELECT receipt_id, fc_code, received_date, product_name,
       shipped_qty, received_qty, damaged_qty, priority,
       ROUND(value_at_risk, 2) AS value_at_risk_usd
FROM v_discrepancy_cases
ORDER BY value_at_risk DESC, received_date DESC
LIMIT 10;
