-- 25_reconciled_order_items.sql
-- Source : staging.order_items (112,650 rows), reconciled.orders, customer_order_map, geolocation, seller
-- Output : reconciled.order_item, one row per order line, typed, with two derived measures
-- Derived:
--   * freight_ratio = freight_value / price        (how much of the line is shipping)
--   * distance_km   = great-circle distance between the seller's zip prefix and the customer's zip prefix
--                     (haversine on the median coordinates; NULL when either prefix has no coordinates)
-- Note: 1,278 orders have items from more than one seller, so the distance is per line, not per order.

CREATE TABLE reconciled.order_item AS
WITH typed AS (
    SELECT i.order_id,
           i.order_item_id::INT                       AS order_item_id,
           i.product_id,
           i.seller_id,
           NULLIF(i.shipping_limit_date, '')::TIMESTAMP AS shipping_limit_ts,
           i.price::NUMERIC(10,2)                     AS price,
           i.freight_value::NUMERIC(10,2)             AS freight_value
    FROM staging.order_items i
),
located AS (
    SELECT t.*,
           gs.lat AS seller_lat, gs.lng AS seller_lng,
           gc.lat AS cust_lat,   gc.lng AS cust_lng
    FROM typed t
    JOIN reconciled.orders o             USING (order_id)
    JOIN reconciled.customer_order_map m ON m.customer_id = o.customer_id
    LEFT JOIN reconciled.geolocation gc  ON gc.zip_prefix = m.zip_prefix
    JOIN reconciled.seller s             ON s.seller_id = t.seller_id
    LEFT JOIN reconciled.geolocation gs  ON gs.zip_prefix = s.zip_prefix
)
SELECT order_id,
       order_item_id,
       product_id,
       seller_id,
       shipping_limit_ts,
       price,
       freight_value,
       ROUND(freight_value / NULLIF(price, 0), 4)                     AS freight_ratio,
       -- haversine formula, Earth radius 6371 km
       ROUND((2 * 6371 * asin(sqrt(
             power(sin(radians(cust_lat - seller_lat) / 2), 2)
           + cos(radians(seller_lat)) * cos(radians(cust_lat))
           * power(sin(radians(cust_lng - seller_lng) / 2), 2)
       )))::NUMERIC, 1)                                                AS distance_km
FROM located;

ALTER TABLE reconciled.order_item ADD PRIMARY KEY (order_id, order_item_id);
