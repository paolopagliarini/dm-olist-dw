-- 23_reconciled_products.sql
-- Source : staging.products (32,951 rows), reconciled.category_translation, reconciled.macro_category
-- Output : reconciled.product, one row per product with the full 3-level category hierarchy
-- Problems solved:
--   * 610 products without category            -> 'unknown'
--   * Portuguese category names                 -> English (2 categories were missing in the Olist translation file)
--   * flat categories                           -> macro-category (top level for roll-up)
--   * dimensions as separate columns            -> volume in cm3 (derived measure, used as product attribute)

CREATE TABLE reconciled.product AS
SELECT p.product_id,
       COALESCE(p.product_category_name, 'unknown')     AS category_pt,
       t.category_en,
       m.macro_category,
       NULLIF(p.product_name_lenght, '')::INT           AS name_length,        -- 'lenght': typo in the source column
       NULLIF(p.product_description_lenght, '')::INT    AS description_length,
       NULLIF(p.product_photos_qty, '')::INT            AS photos_qty,
       NULLIF(p.product_weight_g, '')::INT              AS weight_g,
       NULLIF(p.product_length_cm, '')::INT             AS length_cm,
       NULLIF(p.product_height_cm, '')::INT             AS height_cm,
       NULLIF(p.product_width_cm, '')::INT              AS width_cm,
       NULLIF(p.product_length_cm, '')::INT
         * NULLIF(p.product_height_cm, '')::INT
         * NULLIF(p.product_width_cm, '')::INT          AS volume_cm3
FROM staging.products p
JOIN reconciled.category_translation t ON t.category_pt = COALESCE(p.product_category_name, 'unknown')
JOIN reconciled.macro_category m USING (category_en);

ALTER TABLE reconciled.product ADD PRIMARY KEY (product_id);
