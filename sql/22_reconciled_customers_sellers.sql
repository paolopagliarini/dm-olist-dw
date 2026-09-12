-- 22_reconciled_customers_sellers.sql
-- Sources: staging.customers, staging.sellers, staging.orders, reconciled.geolocation, reconciled.region
-- Outputs:
--   reconciled.customer_order_map : one row per customer_id (= per order), typed.  99,441 rows
--   reconciled.customer           : one row per PERSON (customer_unique_id).        96,096 rows
--   reconciled.seller             : one row per seller.                               3,095 rows
-- Problems solved:
--   * customer_id is generated per order; the real customer key is customer_unique_id
--     (2,997 people bought more than once). The customer entity is built on the person,
--     taking city/state/zip from the most recent order.
--   * seller_city is free text with junk ('sao paulo / sao paulo', 'sbc/sp', '04482255', an e-mail):
--     the city is taken from the geolocation of the seller's zip prefix when available.
--   * coordinates (median per zip prefix) and IBGE region attached to both entities.

-- ---------------------------------------------------------------------------
-- customer_order_map: typed copy of the staging table, used by orders/items to reach the person
-- ---------------------------------------------------------------------------
CREATE TABLE reconciled.customer_order_map AS
SELECT customer_id,
       customer_unique_id,
       customer_zip_code_prefix                 AS zip_prefix,
       unaccent(lower(trim(customer_city)))     AS city,
       customer_state                           AS state_code
FROM staging.customers;

ALTER TABLE reconciled.customer_order_map ADD PRIMARY KEY (customer_id);
CREATE INDEX ON reconciled.customer_order_map (customer_unique_id);

-- ---------------------------------------------------------------------------
-- customer: one row per person, address = the one used in the most recent order
-- ---------------------------------------------------------------------------
CREATE TABLE reconciled.customer AS
WITH latest AS (
    SELECT DISTINCT ON (m.customer_unique_id)
           m.customer_unique_id, m.zip_prefix, m.city, m.state_code
    FROM reconciled.customer_order_map m
    JOIN staging.orders o USING (customer_id)
    ORDER BY m.customer_unique_id, o.order_purchase_timestamp DESC, m.customer_id
),
n_orders AS (
    SELECT customer_unique_id, count(*) AS n_orders
    FROM reconciled.customer_order_map
    GROUP BY customer_unique_id
)
SELECT l.customer_unique_id,
       l.zip_prefix,
       l.city,
       l.state_code,
       r.state_name,
       r.region_name,
       g.lat,
       g.lng,
       n.n_orders
FROM latest l
JOIN reconciled.region r ON r.state_code = l.state_code
LEFT JOIN reconciled.geolocation g ON g.zip_prefix = l.zip_prefix   -- 157 prefixes have no coordinates
JOIN n_orders n USING (customer_unique_id);

ALTER TABLE reconciled.customer ADD PRIMARY KEY (customer_unique_id);

-- ---------------------------------------------------------------------------
-- seller: city from geolocation when possible, otherwise the cleaned free-text city
-- ---------------------------------------------------------------------------
CREATE TABLE reconciled.seller AS
SELECT s.seller_id,
       s.seller_zip_code_prefix AS zip_prefix,
       COALESCE(g.city,
                unaccent(lower(trim(split_part(split_part(s.seller_city, '/', 1), ',', 1))))) AS city,
       s.seller_state           AS state_code,
       r.state_name,
       r.region_name,
       g.lat,
       g.lng
FROM staging.sellers s
JOIN reconciled.region r ON r.state_code = s.seller_state
LEFT JOIN reconciled.geolocation g ON g.zip_prefix = s.seller_zip_code_prefix;   -- 7 prefixes have no coordinates

ALTER TABLE reconciled.seller ADD PRIMARY KEY (seller_id);
