-- DEMO — same question on the fact table and on the materialised view.
\timing on
\echo '--- monthly revenue by macro-category, on fact_order_item'
SELECT d.year_month, p.macro_category, round(sum(f.price)) AS revenue
FROM dw.fact_order_item f
JOIN dw.dim_date d ON d.date_key = f.purchase_date_key
JOIN dw.dim_product p USING (product_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND d.year_month = '2017-11'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5;

\echo '--- same, on mv_monthly_sales'
SELECT year_month, macro_category, round(sum(revenue)) AS revenue
FROM dw.mv_monthly_sales
WHERE status = 'delivered' AND year_month = '2017-11'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5;
\timing off
