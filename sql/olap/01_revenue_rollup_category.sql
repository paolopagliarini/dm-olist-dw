-- OLAP session 01 — Revenue along the product hierarchy
-- Question : where does the money come from, and how concentrated is it?
-- Operations: ROLL-UP  category -> macro-category -> total   (GROUP BY ROLLUP)
--             then DRILL-DOWN inside the top macro-category
-- Facts     : fact_order_item (price)     Dimensions: dim_product (hierarchy), dim_order_status (slice: delivered)

-- Step 1: roll-up. GROUPING() tells which level each row belongs to.
SELECT CASE GROUPING(p.macro_category, p.category_en)
            WHEN 0 THEN 'category' WHEN 1 THEN 'macro-category' ELSE 'TOTAL' END AS level,
       p.macro_category,
       p.category_en,
       count(*)                                    AS n_lines,
       round(sum(f.price))                         AS revenue,
       round(100.0 * sum(f.price) / sum(sum(f.price)) OVER (PARTITION BY GROUPING(p.macro_category, p.category_en)), 1) AS pct_of_level
FROM dw.fact_order_item f
JOIN dw.dim_product      p USING (product_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered'
GROUP BY ROLLUP (p.macro_category, p.category_en)
HAVING GROUPING(p.macro_category, p.category_en) > 0        -- show the two upper levels only
ORDER BY GROUPING(p.macro_category, p.category_en) DESC, revenue DESC;

-- Step 2: drill-down into 'Home & Furniture' (the largest macro-category): its categories, by year.
SELECT p.category_en,
       round(sum(f.price) FILTER (WHERE d.year = 2017)) AS revenue_2017,
       round(sum(f.price) FILTER (WHERE d.year = 2018)) AS revenue_2018,
       round(sum(f.price))                              AS revenue_total,
       round(avg(f.price), 2)                           AS avg_line_price
FROM dw.fact_order_item f
JOIN dw.dim_product      p USING (product_key)
JOIN dw.dim_date         d ON d.date_key = f.purchase_date_key
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND p.macro_category = 'Home & Furniture'
GROUP BY p.category_en
ORDER BY revenue_total DESC;
