-- 50_dw_materialized_views.sql
-- Two pre-aggregated materialised views. They are not part of the model: they are a physical
-- optimisation for the most frequent OLAP sessions (time x product x geography, and delivery by
-- region pair). Refresh with: REFRESH MATERIALIZED VIEW dw.<name>;
-- Compared with the base queries in sql/olap/, they cut the scanned rows from ~112k to a few thousand.

-- ---------------------------------------------------------------------------
-- sales by month x product hierarchy x customer state x status  (from fact_order_item)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW dw.mv_monthly_sales AS
SELECT d.year,
       d.quarter,
       d.month,
       d.year_month,
       p.macro_category,
       p.category_en,
       c.region_name    AS customer_region,
       c.state_code     AS customer_state,
       s.status,
       count(*)                 AS n_lines,
       count(DISTINCT f.order_id) AS n_orders,
       sum(f.price)             AS revenue,
       sum(f.freight_value)     AS freight
FROM dw.fact_order_item f
JOIN dw.dim_date         d ON d.date_key = f.purchase_date_key
JOIN dw.dim_product      p ON p.product_key = f.product_key
JOIN dw.dim_customer     c ON c.customer_key = f.customer_key
JOIN dw.dim_order_status s ON s.status_key = f.status_key
GROUP BY d.year, d.quarter, d.month, d.year_month,
         p.macro_category, p.category_en, c.region_name, c.state_code, s.status;

CREATE INDEX ON dw.mv_monthly_sales (year_month);
CREATE INDEX ON dw.mv_monthly_sales (macro_category, category_en);
CREATE INDEX ON dw.mv_monthly_sales (customer_state);

-- ---------------------------------------------------------------------------
-- delivery performance by seller region x customer region  (single-seller delivered orders)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW dw.mv_delivery_by_region_pair AS
SELECT sr.region_name          AS seller_region,
       cr.region_name          AS customer_region,
       d.year,
       count(*)                AS n_orders,
       avg(o.delivery_days)    AS avg_delivery_days,
       avg(o.estimated_days)   AS avg_estimated_days,
       avg(o.is_late::INT)     AS late_rate,
       avg(i.distance_km)      AS avg_distance_km,
       avg(o.review_score)     AS avg_review_score
FROM dw.fact_order o
JOIN dw.fact_order_item i ON i.order_id = o.order_id AND i.order_item_id = 1   -- one line per order: the seller of line 1
JOIN dw.dim_customer     cr ON cr.customer_key = o.customer_key
JOIN dw.dim_seller       sr ON sr.seller_key = i.seller_key
JOIN dw.dim_date         d  ON d.date_key = o.purchase_date_key
JOIN dw.dim_order_status s  ON s.status_key = o.status_key
WHERE s.status = 'delivered' AND o.n_sellers = 1 AND o.delivery_days IS NOT NULL
GROUP BY sr.region_name, cr.region_name, d.year;
