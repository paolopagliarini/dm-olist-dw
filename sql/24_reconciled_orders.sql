-- 24_reconciled_orders.sql
-- Source : staging.orders (99,441 rows), reconciled.customer_order_map
-- Output : reconciled.orders, one row per order with typed timestamps and derived delivery measures
-- Problems solved:
--   * timestamps stored as text, some empty  -> TIMESTAMP, NULL when missing
--   * customer_id per order                  -> customer_unique_id attached (person)
--   * delivery performance not in the data   -> derived: delivery_days, estimated_days, delay_days, is_late,
--                                               approval_hours, carrier_days
-- Note: 2,965 orders have no delivered date (not delivered yet, canceled, or 8 'delivered' with the date missing):
--       their delivery measures are NULL, they are not dropped.

CREATE TABLE reconciled.orders AS
WITH typed AS (
    SELECT o.order_id,
           o.customer_id,
           m.customer_unique_id,
           o.order_status                                            AS status,
           NULLIF(o.order_purchase_timestamp, '')::TIMESTAMP         AS purchase_ts,
           NULLIF(o.order_approved_at, '')::TIMESTAMP                AS approved_ts,
           NULLIF(o.order_delivered_carrier_date, '')::TIMESTAMP     AS carrier_ts,
           NULLIF(o.order_delivered_customer_date, '')::TIMESTAMP    AS delivered_ts,
           NULLIF(o.order_estimated_delivery_date, '')::TIMESTAMP    AS estimated_ts
    FROM staging.orders o
    JOIN reconciled.customer_order_map m USING (customer_id)
)
SELECT order_id,
       customer_id,
       customer_unique_id,
       status,
       purchase_ts,
       approved_ts,
       carrier_ts,
       delivered_ts,
       estimated_ts,
       purchase_ts::DATE                                              AS purchase_date,
       delivered_ts::DATE                                             AS delivered_date,
       estimated_ts::DATE                                             AS estimated_date,
       (delivered_ts::DATE - purchase_ts::DATE)                       AS delivery_days,    -- actual, purchase -> customer
       (estimated_ts::DATE - purchase_ts::DATE)                       AS estimated_days,   -- promised
       (delivered_ts::DATE - estimated_ts::DATE)                      AS delay_days,       -- >0 late, <0 early
       CASE WHEN delivered_ts IS NULL THEN NULL
            ELSE delivered_ts::DATE > estimated_ts::DATE END          AS is_late,
       ROUND(EXTRACT(EPOCH FROM (approved_ts - purchase_ts)) / 3600, 2) AS approval_hours,
       (carrier_ts::DATE - purchase_ts::DATE)                         AS carrier_days      -- purchase -> handed to carrier
FROM typed;

ALTER TABLE reconciled.orders ADD PRIMARY KEY (order_id);
CREATE INDEX ON reconciled.orders (customer_unique_id);
