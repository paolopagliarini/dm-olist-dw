-- OLAP session 06 — The weight of shipping costs
-- Question : for which products, and at which distances, does shipping cost as much as the product itself?
-- Operations: DICE macro-category x distance band on fact_order_item; ROLL-UP with CUBE for the marginals
-- Facts     : fact_order_item (price, freight_value, freight_ratio, distance_km)   Dimensions: dim_product, dim_order_status
-- freight_ratio = freight_value / price (per line). A ratio >= 1 means the customer paid more for shipping than for the item.

-- Step 1: by macro-category: average freight ratio and share of lines where shipping >= price.
SELECT p.macro_category,
       count(*)                                              AS n_lines,
       round(avg(f.price), 2)                                AS avg_price,
       round(avg(f.freight_value), 2)                        AS avg_freight,
       round(100.0 * sum(f.freight_value) / sum(f.price), 1) AS freight_pct_of_revenue,
       round(100.0 * avg((f.freight_ratio >= 1)::INT), 1)    AS lines_shipping_ge_price_pct
FROM dw.fact_order_item f
JOIN dw.dim_product      p USING (product_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered'
GROUP BY p.macro_category
ORDER BY freight_pct_of_revenue DESC;

-- Step 2: CUBE macro-category x distance band (only the 4 largest macro-categories, to keep the output readable).
SELECT COALESCE(p.macro_category, 'ALL')                     AS macro_category,
       COALESCE(CASE WHEN f.distance_km < 100  THEN '1. < 100 km'
                     WHEN f.distance_km < 500  THEN '2. 100-500 km'
                     WHEN f.distance_km < 1000 THEN '3. 500-1000 km'
                     ELSE                           '4. > 1000 km' END, 'ALL') AS distance_band,
       count(*)                                              AS n_lines,
       round(100.0 * sum(f.freight_value) / sum(f.price), 1) AS freight_pct_of_revenue
FROM dw.fact_order_item f
JOIN dw.dim_product      p USING (product_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND f.distance_km IS NOT NULL
  AND p.macro_category IN ('Home & Furniture', 'Sports & Leisure', 'Health & Beauty', 'Electronics & Computers')
GROUP BY CUBE (p.macro_category,
               CASE WHEN f.distance_km < 100  THEN '1. < 100 km'
                    WHEN f.distance_km < 500  THEN '2. 100-500 km'
                    WHEN f.distance_km < 1000 THEN '3. 500-1000 km'
                    ELSE                           '4. > 1000 km' END)
ORDER BY 1, 2;
