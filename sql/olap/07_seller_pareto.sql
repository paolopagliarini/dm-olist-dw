-- OLAP session 07 — Seller concentration
-- Question : how many sellers make most of the revenue, and does it differ by macro-category?
-- Operations: ranking and cumulative share with WINDOW FUNCTIONS (rank, sum over), then DICE by macro-category
-- Facts     : fact_order_item (price)        Dimensions: dim_seller, dim_product, dim_order_status

-- Step 1: revenue per seller, cumulative share; how many sellers reach 50% and 80% of the revenue.
WITH per_seller AS (
    SELECT s.seller_id, s.state_code, sum(f.price) AS revenue
    FROM dw.fact_order_item f
    JOIN dw.dim_seller       s  USING (seller_key)
    JOIN dw.dim_order_status st USING (status_key)
    WHERE st.status = 'delivered'
    GROUP BY s.seller_id, s.state_code
),
ranked AS (
    SELECT seller_id, state_code, revenue,
           rank() OVER (ORDER BY revenue DESC)                                    AS rnk,
           100.0 * sum(revenue) OVER (ORDER BY revenue DESC) / sum(revenue) OVER () AS cum_pct
    FROM per_seller
)
SELECT count(*)                                   AS n_sellers,
       min(rnk) FILTER (WHERE cum_pct >= 50)      AS sellers_for_50_pct,
       min(rnk) FILTER (WHERE cum_pct >= 80)      AS sellers_for_80_pct,
       round(100.0 * count(*) FILTER (WHERE rnk <= 100) / count(*), 1)          AS top100_as_pct_of_sellers,
       round(max(cum_pct) FILTER (WHERE rnk <= 100), 1)                          AS top100_share_of_revenue
FROM ranked;

-- Step 2: the top 10 sellers.
WITH per_seller AS (
    SELECT s.seller_id, s.city, s.state_code, sum(f.price) AS revenue, count(DISTINCT f.order_id) AS n_orders,
           mode() WITHIN GROUP (ORDER BY p.macro_category) AS main_macro_category
    FROM dw.fact_order_item f
    JOIN dw.dim_seller       s  USING (seller_key)
    JOIN dw.dim_product      p  USING (product_key)
    JOIN dw.dim_order_status st USING (status_key)
    WHERE st.status = 'delivered'
    GROUP BY s.seller_id, s.city, s.state_code
)
SELECT rank() OVER (ORDER BY revenue DESC) AS rnk, left(seller_id, 8) AS seller, city, state_code, main_macro_category,
       n_orders, round(revenue) AS revenue,
       round(100.0 * revenue / sum(revenue) OVER (), 2) AS pct_revenue
FROM per_seller
ORDER BY revenue DESC
LIMIT 10;

-- Step 3: dice by macro-category: share of the top 3 sellers inside each macro-category.
WITH per_cat_seller AS (
    SELECT p.macro_category, s.seller_id, sum(f.price) AS revenue
    FROM dw.fact_order_item f
    JOIN dw.dim_seller       s  USING (seller_key)
    JOIN dw.dim_product      p  USING (product_key)
    JOIN dw.dim_order_status st USING (status_key)
    WHERE st.status = 'delivered'
    GROUP BY p.macro_category, s.seller_id
),
ranked AS (
    SELECT macro_category, seller_id, revenue,
           rank() OVER (PARTITION BY macro_category ORDER BY revenue DESC) AS rnk
    FROM per_cat_seller
)
SELECT macro_category,
       count(*)                                                        AS n_sellers,
       round(sum(revenue))                                             AS revenue,
       round(100.0 * sum(revenue) FILTER (WHERE rnk <= 3) / sum(revenue), 1) AS top3_share_pct
FROM ranked
GROUP BY macro_category
ORDER BY top3_share_pct DESC;
