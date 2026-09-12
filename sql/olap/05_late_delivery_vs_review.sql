-- OLAP session 05 — Late deliveries and customer reviews
-- Question : does a late delivery change what customers think? By how much, and is it the same everywhere?
-- Operations: SLICE (delivered orders with a review), bucketing of delay_days, DICE by customer region, then by year
-- Facts     : fact_order (delay_days, is_late, review_score)      Dimensions: dim_customer (region), dim_date (year)

-- Step 1: average review by delay band. delay_days = delivered date - promised date.
SELECT CASE WHEN o.delay_days <= -14 THEN '1. 2+ weeks early'
            WHEN o.delay_days <  0   THEN '2. early'
            WHEN o.delay_days =  0   THEN '3. on the promised day'
            WHEN o.delay_days <= 7   THEN '4. up to 1 week late'
            WHEN o.delay_days <= 14  THEN '5. 1-2 weeks late'
            ELSE                          '6. more than 2 weeks late' END AS delay_band,
       count(*)                                          AS n_orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_orders,
       round(avg(o.review_score), 2)                     AS avg_review,
       round(100.0 * avg((o.review_score = 1)::INT), 1)  AS one_star_pct,
       round(100.0 * avg((o.review_score = 5)::INT), 1)  AS five_star_pct
FROM dw.fact_order o
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND o.has_review AND o.delay_days IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Step 2: on-time vs late, by customer region (dice): is the penalty the same everywhere?
SELECT c.region_name,
       count(*)                                                        AS n_orders,
       round(100.0 * avg(o.is_late::INT), 1)                           AS late_pct,
       round(avg(o.review_score) FILTER (WHERE NOT o.is_late), 2)      AS review_on_time,
       round(avg(o.review_score) FILTER (WHERE o.is_late), 2)          AS review_late,
       round(avg(o.review_score) FILTER (WHERE NOT o.is_late)
           - avg(o.review_score) FILTER (WHERE o.is_late), 2)          AS penalty
FROM dw.fact_order o
JOIN dw.dim_customer     c USING (customer_key)
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND o.has_review AND o.is_late IS NOT NULL
GROUP BY c.region_name
ORDER BY late_pct DESC;

-- Step 3: by quarter: when were deliveries late, and did the average review follow?
SELECT d.year_quarter,
       count(*)                               AS n_orders,
       round(100.0 * avg(o.is_late::INT), 1)  AS late_pct,
       round(avg(o.delivery_days), 1)         AS avg_delivery_days,
       round(avg(o.review_score), 2)          AS avg_review
FROM dw.fact_order o
JOIN dw.dim_date         d ON d.date_key = o.purchase_date_key
JOIN dw.dim_order_status s USING (status_key)
WHERE s.status = 'delivered' AND o.has_review AND o.is_late IS NOT NULL
  AND d.year_quarter BETWEEN '2017-Q1' AND '2018-Q3'
GROUP BY d.year_quarter
ORDER BY d.year_quarter;
