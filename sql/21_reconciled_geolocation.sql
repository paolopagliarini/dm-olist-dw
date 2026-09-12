-- 21_reconciled_geolocation.sql
-- Source : staging.geolocation (1,000,163 rows, ~52 coordinate samples per zip code prefix)
-- Output : reconciled.geolocation, ONE row per zip code prefix (~19,000 rows)
-- Problems solved:
--   * many points per prefix            -> median latitude / longitude
--   * 42 points outside Brazil          -> discarded with a bounding box
--   * 8 prefixes listed under 2 states  -> keep the most frequent (state, city) pair
--   * city spelling variants            -> unaccent + lower + trim ('são paulo' -> 'sao paulo')
-- Zip prefixes are kept as TEXT because leading zeros are significant ('01037').

CREATE TABLE reconciled.geolocation AS
WITH valid AS (
    SELECT geolocation_zip_code_prefix                    AS zip_prefix,
           geolocation_lat::DOUBLE PRECISION              AS lat,
           geolocation_lng::DOUBLE PRECISION              AS lng,
           unaccent(lower(trim(geolocation_city)))        AS city,
           geolocation_state                              AS state_code
    FROM staging.geolocation
    WHERE geolocation_lat::DOUBLE PRECISION BETWEEN -33.8 AND 5.3     -- Brazil bounding box
      AND geolocation_lng::DOUBLE PRECISION BETWEEN -73.9 AND -34.7
),
-- most frequent (state, city) for each prefix
place AS (
    SELECT DISTINCT ON (zip_prefix) zip_prefix, state_code, city
    FROM (
        SELECT zip_prefix, state_code, city, count(*) AS n
        FROM valid
        GROUP BY zip_prefix, state_code, city
    ) counted
    ORDER BY zip_prefix, n DESC, state_code, city
)
SELECT v.zip_prefix,
       p.city,
       p.state_code,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY v.lat) AS lat,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY v.lng) AS lng,
       count(*)                                           AS n_points
FROM valid v
JOIN place p USING (zip_prefix)
GROUP BY v.zip_prefix, p.city, p.state_code;

ALTER TABLE reconciled.geolocation ADD PRIMARY KEY (zip_prefix);
ALTER TABLE reconciled.geolocation
    ADD CONSTRAINT geolocation_state_fk FOREIGN KEY (state_code) REFERENCES reconciled.region (state_code);
