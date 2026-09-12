-- OLAP session 02 — Revenue along the customer geography hierarchy
-- Question : how is demand distributed across Brazil, and how much is concentrated in São Paulo?
-- Operations: ROLL-UP to region, DRILL-DOWN region -> state (GROUPING SETS), then DRILL-DOWN state -> city (SP)
-- Facts     : fact_order_item        Dimensions: dim_customer (region -> state -> city), dim_order_status (slice)

-- Step 1: region and state levels in one query (GROUPING SETS), with share of national revenue.
SELECT CASE GROUPING(c.region_name, c.state_code) WHEN 0 THEN 'state' ELSE 'region' END AS level,
       c.region_name,
       c.state_code,
       count(DISTINCT f.order_id)                                                 AS n_orders,
       round(sum(f.price))                                                        AS revenue,
       round(100.0 * sum(f.price) / sum(sum(f.price)) OVER (PARTITION BY GROUPING(c.region_name, c.state_code)), 1) AS pct_revenue,
       round(sum(f.price) / count(DISTINCT f.order_id), 2)                        AS revenue_per_order,
       round(100.0 * sum(f.freight_value) / sum(f.price), 1)                      AS freight_pct_of_price
FROM dw.fact_order_item f
JOIN dw.dim_customer     c USING (customer_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered'
GROUP BY GROUPING SETS ((c.region_name), (c.region_name, c.state_code))
ORDER BY GROUPING(c.region_name, c.state_code) DESC, revenue DESC;

-- Step 2: drill-down inside the state of São Paulo: top 10 cities.
SELECT c.city,
       count(DISTINCT f.order_id) AS n_orders,
       round(sum(f.price))        AS revenue,
       round(100.0 * sum(f.price) / sum(sum(f.price)) OVER (), 1) AS pct_of_state
FROM dw.fact_order_item f
JOIN dw.dim_customer     c USING (customer_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND c.state_code = 'SP'
GROUP BY c.city
ORDER BY revenue DESC
LIMIT 10;
