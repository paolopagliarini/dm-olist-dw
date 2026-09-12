-- OLAP session 04 — Delivery performance across the country
-- Question : how long does delivery take, and how often is it late, depending on where the seller and the customer are?
-- Operations: DICE seller region x customer region, then DRILL-ACROSS the two facts (delivery from fact_order,
--             distance and seller from fact_order_item, joined on order_id)
-- Facts     : fact_order (delivery_days, is_late) + fact_order_item (distance_km, seller)
-- Dimensions: dim_seller (region), dim_customer (region), dim_order_status
-- Scope     : delivered orders with a single seller (98.7% of them), so that the seller of the order is well defined.

-- Step 1: where do sellers and customers live? (marginals of the dice)
SELECT 'sellers' AS who, region_name, count(*) AS n, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM dw.dim_seller GROUP BY region_name
UNION ALL
SELECT 'customers', region_name, count(*), round(100.0 * count(*) / sum(count(*)) OVER (), 1)
FROM dw.dim_customer GROUP BY region_name
ORDER BY who, n DESC;

-- Step 2: the dice. One row per (seller region, customer region).
SELECT sr.region_name                       AS seller_region,
       cr.region_name                       AS customer_region,
       count(*)                             AS n_orders,
       round(avg(i.distance_km))            AS avg_km,
       round(avg(o.delivery_days), 1)       AS avg_delivery_days,
       round(avg(o.estimated_days), 1)      AS avg_promised_days,
       round(100.0 * avg(o.is_late::INT), 1) AS late_pct,
       round(avg(o.review_score), 2)        AS avg_review
FROM dw.fact_order o
JOIN dw.fact_order_item i  ON i.order_id = o.order_id AND i.order_item_id = 1
JOIN dw.dim_customer    cr ON cr.customer_key = o.customer_key
JOIN dw.dim_seller      sr ON sr.seller_key = i.seller_key
JOIN dw.dim_order_status s ON s.status_key = o.status_key
WHERE s.status = 'delivered' AND o.n_sellers = 1 AND o.delivery_days IS NOT NULL
GROUP BY sr.region_name, cr.region_name
HAVING count(*) >= 100
ORDER BY avg_delivery_days DESC;

-- Step 3: same question, by distance band instead of region (a second way to cut the same cube).
SELECT CASE WHEN i.distance_km < 100 THEN '< 100 km'
            WHEN i.distance_km < 500 THEN '100-500 km'
            WHEN i.distance_km < 1000 THEN '500-1000 km'
            WHEN i.distance_km < 2000 THEN '1000-2000 km'
            ELSE '> 2000 km' END          AS distance_band,
       count(*)                            AS n_orders,
       round(avg(o.delivery_days), 1)      AS avg_delivery_days,
       round(avg(o.estimated_days), 1)     AS avg_promised_days,
       round(100.0 * avg(o.is_late::INT), 1) AS late_pct,
       round(avg(o.review_score), 2)       AS avg_review
FROM dw.fact_order o
JOIN dw.fact_order_item i ON i.order_id = o.order_id AND i.order_item_id = 1
JOIN dw.dim_order_status s ON s.status_key = o.status_key
WHERE s.status = 'delivered' AND o.n_sellers = 1 AND o.delivery_days IS NOT NULL AND i.distance_km IS NOT NULL
GROUP BY 1
ORDER BY min(i.distance_km);
