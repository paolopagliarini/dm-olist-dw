-- OLAP session 03 — Seasonality of sales
-- Question : how do sales evolve over time, and is there a seasonal peak?
-- Operations: SLICE on the time dimension (comparable months only), PIVOT month x year, DRILL-DOWN to day
-- Facts     : fact_order (orders, total_price)     Dimensions: dim_date (year -> month -> day), dim_order_status
-- Note on the data: Sept-Dec 2016 (329 orders) and Sept-Oct 2018 (20 orders) are almost empty,
--                   so year-over-year comparisons use Jan-Aug only, the months present in both 2017 and 2018.

-- Step 1: monthly series (all months), with month-over-month growth (window function).
SELECT d.year_month,
       count(*)                       AS n_orders,
       round(sum(o.total_price))      AS revenue,
       round(100.0 * (sum(o.total_price) - lag(sum(o.total_price)) OVER (ORDER BY d.year_month))
                   / lag(sum(o.total_price)) OVER (ORDER BY d.year_month), 1) AS mom_growth_pct
FROM dw.fact_order o
JOIN dw.dim_date         d ON d.date_key = o.purchase_date_key
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND d.year_month BETWEEN '2017-01' AND '2018-08'
GROUP BY d.year_month
ORDER BY d.year_month;

-- Step 2: pivot month x year for the comparable months (Jan-Aug), with year-over-year growth.
SELECT d.month,
       d.month_name,
       count(*)                  FILTER (WHERE d.year = 2017) AS orders_2017,
       count(*)                  FILTER (WHERE d.year = 2018) AS orders_2018,
       round(sum(o.total_price)  FILTER (WHERE d.year = 2017)) AS revenue_2017,
       round(sum(o.total_price)  FILTER (WHERE d.year = 2018)) AS revenue_2018,
       round(100.0 * (sum(o.total_price) FILTER (WHERE d.year = 2018) - sum(o.total_price) FILTER (WHERE d.year = 2017))
                   /  sum(o.total_price) FILTER (WHERE d.year = 2017), 1) AS yoy_growth_pct
FROM dw.fact_order o
JOIN dw.dim_date         d ON d.date_key = o.purchase_date_key
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND d.year IN (2017, 2018) AND d.month BETWEEN 1 AND 8
GROUP BY d.month, d.month_name
ORDER BY d.month;

-- Step 3: drill-down to the day: the 5 busiest days (Black Friday 2017 = 24 November).
SELECT d.full_date, d.day_name, count(*) AS n_orders, round(sum(o.total_price)) AS revenue
FROM dw.fact_order o
JOIN dw.dim_date d ON d.date_key = o.purchase_date_key
GROUP BY d.full_date, d.day_name
ORDER BY n_orders DESC
LIMIT 5;
