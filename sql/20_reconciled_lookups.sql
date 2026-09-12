-- 20_reconciled_lookups.sql
-- Small reference tables that are NOT in the Olist files and are needed to build hierarchies:
--   region               : 27 Brazilian states -> 5 IBGE macro-regions (external source: IBGE)
--   category_translation : Portuguese -> English category names (Olist file + 2 missing rows + 'unknown')
--   macro_category       : 73 English categories -> 12 macro-categories (defined by us, top level of the product hierarchy)
-- These lookups turn flat codes into the levels used by roll-up / drill-down in the OLAP sessions.

-- ---------------------------------------------------------------------------
-- 1) Brazilian states and macro-regions (IBGE classification)
-- ---------------------------------------------------------------------------
CREATE TABLE reconciled.region (
    state_code  CHAR(2)     PRIMARY KEY,
    state_name  TEXT        NOT NULL,
    region_name TEXT        NOT NULL
);

INSERT INTO reconciled.region (state_code, state_name, region_name) VALUES
    ('AC', 'Acre',                'North'),
    ('AM', 'Amazonas',            'North'),
    ('AP', 'Amapa',               'North'),
    ('PA', 'Para',                'North'),
    ('RO', 'Rondonia',            'North'),
    ('RR', 'Roraima',             'North'),
    ('TO', 'Tocantins',           'North'),
    ('AL', 'Alagoas',             'Northeast'),
    ('BA', 'Bahia',               'Northeast'),
    ('CE', 'Ceara',               'Northeast'),
    ('MA', 'Maranhao',            'Northeast'),
    ('PB', 'Paraiba',             'Northeast'),
    ('PE', 'Pernambuco',          'Northeast'),
    ('PI', 'Piaui',               'Northeast'),
    ('RN', 'Rio Grande do Norte', 'Northeast'),
    ('SE', 'Sergipe',             'Northeast'),
    ('DF', 'Distrito Federal',    'Central-West'),
    ('GO', 'Goias',               'Central-West'),
    ('MS', 'Mato Grosso do Sul',  'Central-West'),
    ('MT', 'Mato Grosso',         'Central-West'),
    ('ES', 'Espirito Santo',      'Southeast'),
    ('MG', 'Minas Gerais',        'Southeast'),
    ('RJ', 'Rio de Janeiro',      'Southeast'),
    ('SP', 'Sao Paulo',           'Southeast'),
    ('PR', 'Parana',              'South'),
    ('RS', 'Rio Grande do Sul',   'South'),
    ('SC', 'Santa Catarina',      'South');

-- ---------------------------------------------------------------------------
-- 2) Category translation: the Olist file misses 2 categories used by products,
--    and products with NULL category are mapped to 'unknown'.
-- ---------------------------------------------------------------------------
CREATE TABLE reconciled.category_translation (
    category_pt TEXT PRIMARY KEY,
    category_en TEXT NOT NULL
);

INSERT INTO reconciled.category_translation (category_pt, category_en)
SELECT product_category_name, product_category_name_english
FROM staging.product_category_translation;

INSERT INTO reconciled.category_translation (category_pt, category_en) VALUES
    ('pc_gamer',                                      'pc_gamer'),
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'),
    ('unknown',                                       'unknown');

-- ---------------------------------------------------------------------------
-- 3) Macro-categories: top level of the product hierarchy (product -> category -> macro-category).
--    Grouping defined by us on the 73 Olist categories; the original names are kept as they are
--    (including Olist's typos such as 'costruction_tools_garden' or 'home_confort').
-- ---------------------------------------------------------------------------
-- category_en is unique in the translation file, so it can be referenced by the macro-category table
ALTER TABLE reconciled.category_translation ADD CONSTRAINT category_translation_en_unique UNIQUE (category_en);

CREATE TABLE reconciled.macro_category (
    category_en    TEXT PRIMARY KEY REFERENCES reconciled.category_translation (category_en),
    macro_category TEXT NOT NULL
);

INSERT INTO reconciled.macro_category (category_en, macro_category) VALUES
    -- Home & Furniture
    ('bed_bath_table',                          'Home & Furniture'),
    ('furniture_decor',                         'Home & Furniture'),
    ('furniture_bedroom',                       'Home & Furniture'),
    ('furniture_living_room',                   'Home & Furniture'),
    ('furniture_mattress_and_upholstery',       'Home & Furniture'),
    ('kitchen_dining_laundry_garden_furniture', 'Home & Furniture'),
    ('office_furniture',                        'Home & Furniture'),
    ('housewares',                              'Home & Furniture'),
    ('home_confort',                            'Home & Furniture'),
    ('home_comfort_2',                          'Home & Furniture'),
    ('la_cuisine',                              'Home & Furniture'),
    ('portable_kitchen_and_food_preparers',     'Home & Furniture'),
    ('flowers',                                 'Home & Furniture'),
    -- Appliances
    ('home_appliances',                         'Appliances'),
    ('home_appliances_2',                       'Appliances'),
    ('small_appliances',                        'Appliances'),
    ('small_appliances_home_oven_and_coffee',   'Appliances'),
    ('air_conditioning',                        'Appliances'),
    -- Electronics & Computers
    ('electronics',                             'Electronics & Computers'),
    ('computers',                               'Electronics & Computers'),
    ('computers_accessories',                   'Electronics & Computers'),
    ('pc_gamer',                                'Electronics & Computers'),
    ('tablets_printing_image',                  'Electronics & Computers'),
    ('telephony',                               'Electronics & Computers'),
    ('fixed_telephony',                         'Electronics & Computers'),
    ('audio',                                   'Electronics & Computers'),
    ('consoles_games',                          'Electronics & Computers'),
    ('cine_photo',                              'Electronics & Computers'),
    -- Fashion & Accessories
    ('fashio_female_clothing',                  'Fashion & Accessories'),
    ('fashion_bags_accessories',                'Fashion & Accessories'),
    ('fashion_childrens_clothes',               'Fashion & Accessories'),
    ('fashion_male_clothing',                   'Fashion & Accessories'),
    ('fashion_shoes',                           'Fashion & Accessories'),
    ('fashion_sport',                           'Fashion & Accessories'),
    ('fashion_underwear_beach',                 'Fashion & Accessories'),
    ('luggage_accessories',                     'Fashion & Accessories'),
    ('watches_gifts',                           'Fashion & Accessories'),
    -- Health & Beauty
    ('health_beauty',                           'Health & Beauty'),
    ('perfumery',                               'Health & Beauty'),
    -- Sports & Leisure
    ('sports_leisure',                          'Sports & Leisure'),
    ('toys',                                    'Sports & Leisure'),
    ('cool_stuff',                              'Sports & Leisure'),
    ('party_supplies',                          'Sports & Leisure'),
    ('christmas_supplies',                      'Sports & Leisure'),
    ('musical_instruments',                     'Sports & Leisure'),
    -- Books, Media & Stationery
    ('books_general_interest',                  'Books, Media & Stationery'),
    ('books_imported',                          'Books, Media & Stationery'),
    ('books_technical',                         'Books, Media & Stationery'),
    ('cds_dvds_musicals',                       'Books, Media & Stationery'),
    ('dvds_blu_ray',                            'Books, Media & Stationery'),
    ('music',                                   'Books, Media & Stationery'),
    ('stationery',                              'Books, Media & Stationery'),
    ('art',                                     'Books, Media & Stationery'),
    ('arts_and_craftmanship',                   'Books, Media & Stationery'),
    -- Tools, Construction & Garden
    ('construction_tools_construction',         'Tools, Construction & Garden'),
    ('construction_tools_lights',               'Tools, Construction & Garden'),
    ('construction_tools_safety',               'Tools, Construction & Garden'),
    ('costruction_tools_garden',                'Tools, Construction & Garden'),
    ('costruction_tools_tools',                 'Tools, Construction & Garden'),
    ('home_construction',                       'Tools, Construction & Garden'),
    ('garden_tools',                            'Tools, Construction & Garden'),
    ('signaling_and_security',                  'Tools, Construction & Garden'),
    ('security_and_services',                   'Tools, Construction & Garden'),
    -- Food & Drink
    ('food',                                    'Food & Drink'),
    ('drinks',                                  'Food & Drink'),
    ('food_drink',                              'Food & Drink'),
    -- Auto, Industry & Marketplace
    ('auto',                                    'Auto, Industry & Marketplace'),
    ('agro_industry_and_commerce',              'Auto, Industry & Marketplace'),
    ('industry_commerce_and_business',          'Auto, Industry & Marketplace'),
    ('market_place',                            'Auto, Industry & Marketplace'),
    -- Baby & Pets
    ('baby',                                    'Baby & Pets'),
    ('pet_shop',                                'Baby & Pets'),
    ('diapers_and_hygiene',                     'Baby & Pets'),
    -- Unknown
    ('unknown',                                 'Unknown');

-- Every translated category must have a macro-category, otherwise the product hierarchy has holes.
DO $$
DECLARE missing INT;
BEGIN
    SELECT count(*) INTO missing
    FROM reconciled.category_translation t
    LEFT JOIN reconciled.macro_category m USING (category_en)
    WHERE m.category_en IS NULL;
    IF missing > 0 THEN
        RAISE EXCEPTION '% categories without macro-category', missing;
    END IF;
END $$;
