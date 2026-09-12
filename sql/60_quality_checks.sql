-- 60_quality_checks.sql
-- Sanity checks on the star schema. Any failure raises an exception and stops run_all.sh.
-- The expected numbers come from profiling the raw files and from the reconciled layer;
-- they make sure the ETL neither loses nor duplicates rows, and that the two facts agree.

DO $$
DECLARE
    v_facts_order      BIGINT;
    v_facts_item       BIGINT;
    v_dim_customer     BIGINT;
    v_dim_seller       BIGINT;
    v_dim_product      BIGINT;
    v_sum_price_order  NUMERIC;
    v_sum_price_item   NUMERIC;
    v_sum_freight_o    NUMERIC;
    v_sum_freight_i    NUMERIC;
    v_bad_late         BIGINT;
    v_bad_items        BIGINT;
    v_no_review        BIGINT;
    v_date_gap         BIGINT;
BEGIN
    -- 1. row counts: nothing lost, nothing duplicated
    SELECT count(*) INTO v_facts_order  FROM dw.fact_order;
    SELECT count(*) INTO v_facts_item   FROM dw.fact_order_item;
    SELECT count(*) INTO v_dim_customer FROM dw.dim_customer;
    SELECT count(*) INTO v_dim_seller   FROM dw.dim_seller;
    SELECT count(*) INTO v_dim_product  FROM dw.dim_product;
    IF v_facts_order  <> (SELECT count(*) FROM staging.orders)      THEN RAISE EXCEPTION 'fact_order rows % <> staging.orders',     v_facts_order;  END IF;
    IF v_facts_item   <> (SELECT count(*) FROM staging.order_items) THEN RAISE EXCEPTION 'fact_order_item rows % <> staging.order_items', v_facts_item; END IF;
    IF v_dim_customer <> (SELECT count(DISTINCT customer_unique_id) FROM staging.customers) THEN RAISE EXCEPTION 'dim_customer rows %', v_dim_customer; END IF;
    IF v_dim_seller   <> (SELECT count(*) FROM staging.sellers)     THEN RAISE EXCEPTION 'dim_seller rows %',   v_dim_seller;   END IF;
    IF v_dim_product  <> (SELECT count(*) FROM staging.products)    THEN RAISE EXCEPTION 'dim_product rows %',  v_dim_product;  END IF;

    -- 2. the two facts agree on money
    SELECT sum(total_price), sum(total_freight) INTO v_sum_price_order, v_sum_freight_o FROM dw.fact_order;
    SELECT sum(price),       sum(freight_value) INTO v_sum_price_item,  v_sum_freight_i FROM dw.fact_order_item;
    IF v_sum_price_order <> v_sum_price_item THEN RAISE EXCEPTION 'total_price % <> sum(price) %', v_sum_price_order, v_sum_price_item; END IF;
    IF v_sum_freight_o   <> v_sum_freight_i  THEN RAISE EXCEPTION 'total_freight % <> sum(freight) %', v_sum_freight_o, v_sum_freight_i; END IF;

    -- 3. n_items in fact_order = number of lines in fact_order_item
    SELECT count(*) INTO v_bad_items
    FROM dw.fact_order o
    LEFT JOIN (SELECT order_id, count(*) n FROM dw.fact_order_item GROUP BY order_id) i USING (order_id)
    WHERE o.n_items <> COALESCE(i.n, 0);
    IF v_bad_items > 0 THEN RAISE EXCEPTION '% orders with inconsistent n_items', v_bad_items; END IF;

    -- 4. is_late consistent with delay_days
    SELECT count(*) INTO v_bad_late
    FROM dw.fact_order
    WHERE (is_late AND delay_days <= 0) OR (NOT is_late AND delay_days > 0) OR (is_late IS NULL AND delivered_date_key IS NOT NULL);
    IF v_bad_late > 0 THEN RAISE EXCEPTION '% orders with inconsistent is_late', v_bad_late; END IF;

    -- 5. every order with a review in the reconciled layer has a score in the fact
    SELECT count(*) INTO v_no_review FROM dw.fact_order WHERE has_review AND review_score IS NULL;
    IF v_no_review > 0 THEN RAISE EXCEPTION '% orders flagged has_review without score', v_no_review; END IF;

    -- 6. dim_date has no holes (one row per day between min and max)
    SELECT (max(full_date) - min(full_date) + 1) - count(*) INTO v_date_gap FROM dw.dim_date;
    IF v_date_gap <> 0 THEN RAISE EXCEPTION 'dim_date has % missing days', v_date_gap; END IF;

    RAISE NOTICE 'quality checks passed: % orders, % order lines, % customers, % sellers, % products',
        v_facts_order, v_facts_item, v_dim_customer, v_dim_seller, v_dim_product;
END $$;

-- summary printed by run_all.sh
SELECT 'dw.' || table_name AS table_name,
       (xpath('/row/c/text()', query_to_xml('SELECT count(*) AS c FROM dw.' || table_name, false, true, '')))[1]::TEXT::BIGINT AS rows
FROM information_schema.tables
WHERE table_schema = 'dw' AND table_type = 'BASE TABLE'
ORDER BY 1;
