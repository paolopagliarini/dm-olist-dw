-- 40_dw_facts.sql
-- Fact tables of the star schema. Two facts at two different grains, sharing (conformed) dimensions:
--
--   fact_order_item : grain = one order line (order_id, order_item_id).           112,650 rows
--                     measures that exist at line level: price, freight, freight ratio, seller->customer distance.
--   fact_order      : grain = one order.                                             99,441 rows
--                     measures that exist at order level: number of items/sellers, totals, payment,
--                     delivery time and delay, review score.
--
-- Why two facts: delivery time and review score belong to the ORDER. Copying them on every line of a
-- multi-item order would count them several times in averages (9,803 orders have 2+ lines). Keeping them
-- in a fact at the right grain avoids that; the two facts can still be combined (drill-across) on order_id.
--
-- Additivity notes:
--   price, freight_value, total_price, total_freight, total_paid, n_items : additive
--   delivery_days, delay_days, distance_km, freight_ratio, approval_hours : additive only as averages (non additive over sums)
--   review_score : non additive (a judgement) -> use avg / distribution, never sum
--   is_late, has_review : flags -> counted with COUNT / AVG (rate)

-- ---------------------------------------------------------------------------
-- fact_order_item
-- ---------------------------------------------------------------------------
CREATE TABLE dw.fact_order_item (
    order_id           TEXT           NOT NULL,
    order_item_id      INT            NOT NULL,
    purchase_date_key  INT            NOT NULL REFERENCES dw.dim_date (date_key),
    customer_key       INT            NOT NULL REFERENCES dw.dim_customer (customer_key),
    seller_key         INT            NOT NULL REFERENCES dw.dim_seller (seller_key),
    product_key        INT            NOT NULL REFERENCES dw.dim_product (product_key),
    status_key         INT            NOT NULL REFERENCES dw.dim_order_status (status_key),   -- order attribute, replicated for slicing
    price              NUMERIC(10,2)  NOT NULL,
    freight_value      NUMERIC(10,2)  NOT NULL,
    freight_ratio      NUMERIC(8,4),
    distance_km        NUMERIC(8,1),
    PRIMARY KEY (order_id, order_item_id)
);

INSERT INTO dw.fact_order_item
SELECT i.order_id,
       i.order_item_id,
       to_char(o.purchase_date, 'YYYYMMDD')::INT,
       c.customer_key,
       s.seller_key,
       p.product_key,
       st.status_key,
       i.price,
       i.freight_value,
       i.freight_ratio,
       i.distance_km
FROM reconciled.order_item i
JOIN reconciled.orders     o  ON o.order_id = i.order_id
JOIN dw.dim_customer       c  ON c.customer_unique_id = o.customer_unique_id
JOIN dw.dim_seller         s  ON s.seller_id = i.seller_id
JOIN dw.dim_product        p  ON p.product_id = i.product_id
JOIN dw.dim_order_status   st ON st.status = o.status;

CREATE INDEX ON dw.fact_order_item (purchase_date_key);
CREATE INDEX ON dw.fact_order_item (customer_key);
CREATE INDEX ON dw.fact_order_item (seller_key);
CREATE INDEX ON dw.fact_order_item (product_key);
CREATE INDEX ON dw.fact_order_item (status_key);

-- ---------------------------------------------------------------------------
-- fact_order
-- ---------------------------------------------------------------------------
CREATE TABLE dw.fact_order (
    order_id            TEXT           PRIMARY KEY,
    purchase_date_key   INT            NOT NULL REFERENCES dw.dim_date (date_key),
    delivered_date_key  INT                     REFERENCES dw.dim_date (date_key),   -- NULL if not delivered
    estimated_date_key  INT            NOT NULL REFERENCES dw.dim_date (date_key),
    customer_key        INT            NOT NULL REFERENCES dw.dim_customer (customer_key),
    status_key          INT            NOT NULL REFERENCES dw.dim_order_status (status_key),
    payment_type_key    INT            NOT NULL REFERENCES dw.dim_payment_type (payment_type_key),
    n_items             INT            NOT NULL,   -- 0 for the 775 orders without lines
    n_sellers           INT            NOT NULL,
    total_price         NUMERIC(12,2)  NOT NULL,
    total_freight       NUMERIC(12,2)  NOT NULL,
    total_paid          NUMERIC(12,2),
    n_payments          INT,
    n_installments      INT,
    delivery_days       INT,
    estimated_days      INT,
    delay_days          INT,
    is_late             BOOLEAN,
    approval_hours      NUMERIC(10,2),
    carrier_days        INT,
    review_score        SMALLINT,
    has_review          BOOLEAN        NOT NULL
);

INSERT INTO dw.fact_order
SELECT o.order_id,
       to_char(o.purchase_date,  'YYYYMMDD')::INT,
       to_char(o.delivered_date, 'YYYYMMDD')::INT,
       to_char(o.estimated_date, 'YYYYMMDD')::INT,
       c.customer_key,
       st.status_key,
       pt.payment_type_key,
       COALESCE(li.n_items, 0),
       COALESCE(li.n_sellers, 0),
       COALESCE(li.total_price, 0),
       COALESCE(li.total_freight, 0),
       pay.total_paid,
       pay.n_payments,
       pay.n_installments,
       o.delivery_days,
       o.estimated_days,
       o.delay_days,
       o.is_late,
       o.approval_hours,
       o.carrier_days,
       r.score,
       (r.order_id IS NOT NULL)
FROM reconciled.orders o
JOIN dw.dim_customer     c  ON c.customer_unique_id = o.customer_unique_id
JOIN dw.dim_order_status st ON st.status = o.status
LEFT JOIN reconciled.order_payment pay ON pay.order_id = o.order_id
JOIN dw.dim_payment_type pt ON pt.payment_type = COALESCE(pay.main_payment_type, 'none')
LEFT JOIN (
    SELECT order_id,
           count(*)                  AS n_items,
           count(DISTINCT seller_id) AS n_sellers,
           sum(price)                AS total_price,
           sum(freight_value)        AS total_freight
    FROM reconciled.order_item
    GROUP BY order_id
) li ON li.order_id = o.order_id
LEFT JOIN reconciled.review r ON r.order_id = o.order_id;

CREATE INDEX ON dw.fact_order (purchase_date_key);
CREATE INDEX ON dw.fact_order (delivered_date_key);
CREATE INDEX ON dw.fact_order (customer_key);
CREATE INDEX ON dw.fact_order (status_key);
CREATE INDEX ON dw.fact_order (payment_type_key);
