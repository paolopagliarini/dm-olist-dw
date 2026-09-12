-- 30_dw_dimensions.sql
-- Dimension tables of the star schema (schema dw). Every dimension has a surrogate integer key
-- and keeps the natural key from the reconciled layer. Hierarchies are stored denormalised
-- (star schema, not snowflake): each level is a column of the same table.
--
--   dim_date          day -> month -> quarter -> year  (also week, day of week)        role-playing: purchase / delivered / estimated
--   dim_customer      person -> zip prefix -> city -> state -> region
--   dim_seller        seller -> zip prefix -> city -> state -> region
--   dim_product       product -> category -> macro-category  (+ descriptive attributes)
--   dim_payment_type  5 payment types + 'none'
--   dim_order_status  8 order statuses

-- ---------------------------------------------------------------------------
-- dim_date: one row per calendar day from the first purchase to the last estimated/delivered date
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_date (
    date_key      INT       PRIMARY KEY,          -- yyyymmdd, e.g. 20171124
    full_date     DATE      NOT NULL UNIQUE,
    day           SMALLINT  NOT NULL,
    day_of_week   SMALLINT  NOT NULL,             -- 1 = Monday ... 7 = Sunday (ISO)
    day_name      TEXT      NOT NULL,
    is_weekend    BOOLEAN   NOT NULL,
    week_of_year  SMALLINT  NOT NULL,
    month         SMALLINT  NOT NULL,
    month_name    TEXT      NOT NULL,
    year_month    TEXT      NOT NULL,             -- '2017-11'  (handy label for time series)
    quarter       SMALLINT  NOT NULL,
    year_quarter  TEXT      NOT NULL,             -- '2017-Q4'
    year          SMALLINT  NOT NULL
);

INSERT INTO dw.dim_date
SELECT to_char(d, 'YYYYMMDD')::INT,
       d,
       EXTRACT(DAY FROM d),
       EXTRACT(ISODOW FROM d),
       to_char(d, 'Day'),
       EXTRACT(ISODOW FROM d) IN (6, 7),
       EXTRACT(WEEK FROM d),
       EXTRACT(MONTH FROM d),
       to_char(d, 'Month'),
       to_char(d, 'YYYY-MM'),
       EXTRACT(QUARTER FROM d),
       to_char(d, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM d),
       EXTRACT(YEAR FROM d)
FROM generate_series(
        (SELECT min(purchase_date) FROM reconciled.orders),
        (SELECT greatest(max(estimated_date), max(delivered_date)) FROM reconciled.orders),
        INTERVAL '1 day') AS d;

-- trim the blank padding of to_char('Day') / to_char('Month')
UPDATE dw.dim_date SET day_name = trim(day_name), month_name = trim(month_name);

-- ---------------------------------------------------------------------------
-- dim_customer: one row per person (geographic hierarchy denormalised)
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_customer (
    customer_key        SERIAL   PRIMARY KEY,
    customer_unique_id  TEXT     NOT NULL UNIQUE,
    zip_prefix          TEXT     NOT NULL,
    city                TEXT     NOT NULL,
    state_code          CHAR(2)  NOT NULL,
    state_name          TEXT     NOT NULL,
    region_name         TEXT     NOT NULL,
    lat                 DOUBLE PRECISION,
    lng                 DOUBLE PRECISION,
    n_orders            INT      NOT NULL
);

INSERT INTO dw.dim_customer (customer_unique_id, zip_prefix, city, state_code, state_name, region_name, lat, lng, n_orders)
SELECT customer_unique_id, zip_prefix, city, state_code, state_name, region_name, lat, lng, n_orders
FROM reconciled.customer
ORDER BY customer_unique_id;

-- ---------------------------------------------------------------------------
-- dim_seller
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_seller (
    seller_key   SERIAL   PRIMARY KEY,
    seller_id    TEXT     NOT NULL UNIQUE,
    zip_prefix   TEXT     NOT NULL,
    city         TEXT     NOT NULL,
    state_code   CHAR(2)  NOT NULL,
    state_name   TEXT     NOT NULL,
    region_name  TEXT     NOT NULL,
    lat          DOUBLE PRECISION,
    lng          DOUBLE PRECISION
);

INSERT INTO dw.dim_seller (seller_id, zip_prefix, city, state_code, state_name, region_name, lat, lng)
SELECT seller_id, zip_prefix, city, state_code, state_name, region_name, lat, lng
FROM reconciled.seller
ORDER BY seller_id;

-- ---------------------------------------------------------------------------
-- dim_product: product -> category -> macro-category
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_product (
    product_key         SERIAL  PRIMARY KEY,
    product_id          TEXT    NOT NULL UNIQUE,
    category_pt         TEXT    NOT NULL,
    category_en         TEXT    NOT NULL,
    macro_category      TEXT    NOT NULL,
    weight_g            INT,
    volume_cm3          INT,
    photos_qty          INT,
    name_length         INT,
    description_length  INT
);

INSERT INTO dw.dim_product (product_id, category_pt, category_en, macro_category, weight_g, volume_cm3, photos_qty, name_length, description_length)
SELECT product_id, category_pt, category_en, macro_category, weight_g, volume_cm3, photos_qty, name_length, description_length
FROM reconciled.product
ORDER BY product_id;

-- ---------------------------------------------------------------------------
-- dim_payment_type: the payment types found in the data + 'none' (1 order has no payment row)
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_payment_type (
    payment_type_key  SERIAL  PRIMARY KEY,
    payment_type      TEXT    NOT NULL UNIQUE
);

INSERT INTO dw.dim_payment_type (payment_type)
SELECT DISTINCT main_payment_type FROM reconciled.order_payment
UNION SELECT 'none'
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- dim_order_status
-- ---------------------------------------------------------------------------
CREATE TABLE dw.dim_order_status (
    status_key  SERIAL  PRIMARY KEY,
    status      TEXT    NOT NULL UNIQUE
);

INSERT INTO dw.dim_order_status (status)
SELECT DISTINCT status FROM reconciled.orders ORDER BY 1;
