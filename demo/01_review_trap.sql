-- DEMO — one of the data-quality traps, live: an order with two reviews in the raw file, one in the reconciled layer.
\echo '--- staging: raw rows for one order that has 2 reviews'
SELECT order_id, review_id, review_score, review_creation_date, review_answer_timestamp
FROM staging.order_reviews
WHERE order_id = (SELECT order_id FROM staging.order_reviews GROUP BY order_id HAVING count(*) > 1 ORDER BY order_id LIMIT 1)
ORDER BY review_answer_timestamp;

\echo '--- reconciled: one review per order (the most recent)'
SELECT order_id, review_id, score, creation_date, answer_ts
FROM reconciled.review
WHERE order_id = (SELECT order_id FROM staging.order_reviews GROUP BY order_id HAVING count(*) > 1 ORDER BY order_id LIMIT 1);

\echo '--- how many orders were affected'
SELECT count(*) AS orders_with_2plus_reviews FROM (SELECT order_id FROM staging.order_reviews GROUP BY 1 HAVING count(*) > 1) x;
