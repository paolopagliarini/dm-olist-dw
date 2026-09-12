-- 26_reconciled_payments.sql
-- Source : staging.order_payments (103,886 rows: one row per payment, an order can have several)
-- Output : reconciled.order_payment, ONE row per order (98,666 minus 1 order with no payment = 99,440)
-- Problems solved:
--   * several payment rows per order (instalments, vouchers + card)  -> aggregated per order:
--       main_payment_type = type of the row with the highest value, n_payments, n_installments (max), total_paid (sum)
--   * payment_type 'not_defined' (3 rows)                            -> 'unknown'

CREATE TABLE reconciled.order_payment AS
WITH typed AS (
    SELECT order_id,
           payment_sequential::INT                                       AS payment_sequential,
           CASE WHEN payment_type = 'not_defined' THEN 'unknown' ELSE payment_type END AS payment_type,
           payment_installments::INT                                     AS payment_installments,
           payment_value::NUMERIC(10,2)                                  AS payment_value
    FROM staging.order_payments
),
main AS (
    SELECT DISTINCT ON (order_id) order_id, payment_type AS main_payment_type
    FROM typed
    ORDER BY order_id, payment_value DESC, payment_sequential
)
SELECT t.order_id,
       m.main_payment_type,
       count(*)                 AS n_payments,
       max(payment_installments) AS n_installments,
       sum(payment_value)       AS total_paid
FROM typed t
JOIN main m USING (order_id)
GROUP BY t.order_id, m.main_payment_type;

ALTER TABLE reconciled.order_payment ADD PRIMARY KEY (order_id);
