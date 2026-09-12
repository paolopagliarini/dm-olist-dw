-- 27_reconciled_reviews.sql
-- Source : staging.order_reviews (99,224 rows)
-- Output : reconciled.review, ONE row per order (98,673 rows; 768 orders have no review)
-- Problems solved:
--   * review_id is NOT unique: 789 review ids are attached to more than one order (data export artefact);
--     the natural key of a review in this dataset is therefore the order, not review_id
--   * 547 orders have more than one review -> keep the most recent one (answer timestamp, then creation date)
-- A review is a judgement, not an additive quantity: keeping one per order avoids averaging two opinions
-- of the same customer on the same order.

CREATE TABLE reconciled.review AS
SELECT DISTINCT ON (order_id)
       order_id,
       review_id,
       review_score::INT                                     AS score,
       (NULLIF(review_comment_message, '') IS NOT NULL)      AS has_comment,
       NULLIF(review_creation_date, '')::DATE                AS creation_date,
       NULLIF(review_answer_timestamp, '')::TIMESTAMP        AS answer_ts
FROM staging.order_reviews
ORDER BY order_id,
         NULLIF(review_answer_timestamp, '')::TIMESTAMP DESC NULLS LAST,
         NULLIF(review_creation_date, '')::DATE DESC NULLS LAST,
         review_id;

ALTER TABLE reconciled.review ADD PRIMARY KEY (order_id);
