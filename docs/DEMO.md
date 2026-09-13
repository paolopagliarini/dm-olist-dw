# Live demo — 5 minutes

Terminal font large, window ~120 columns. Database already built before the call; the rebuild is repeated live
because it takes ~10 s. Everything below is a file, nothing is typed from memory.

```bash
cd ~/Desktop/dm-olist-dw
export PATH="/opt/homebrew/opt/postgresql@14/bin:$PATH"
```

| time | what to show | command | what to say |
|---|---|---|---|
| 0:00 | rebuild from scratch | `scripts/run_all.sh` | "Nine CSV files → staging → reconciled → star schema, all SQL, with the quality checks at the end. Ten seconds." Point at the row counts and at `quality checks passed`. |
| 0:40 | the three layers | `psql -d olist_dw` then `\i demo/psqlrc`, `\dt staging.*`, `\dt reconciled.*`, `\dt dw.*` | "Staging is the raw files, all text. Reconciled is typed and cleaned, one table per entity. dw is the star schema: six dimensions, two facts." |
| 1:20 | one data-quality trap, live | `\i demo/01_review_trap.sql` | "This order has two reviews in the file, and the customer changed the score. The reconciled layer keeps one per order, the most recent. 547 orders have two or more reviews, 202 of them with different scores." |
| 2:20 | OLAP session 05 | `\i sql/olap/05_late_delivery_vs_review.sql` (scroll to step 1) | "Delay bands: early deliveries earn nothing, one day late costs 1.3 stars, one week late and 70 % of reviews are one star. The penalty is the same in every region — step 2." |
| 3:20 | OLAP session 04, step 3 | `\i sql/olap/04_delivery_by_region_pair.sql` (scroll to the distance bands) | "Distance drives days, late rate and review together. The distance comes from the coordinates we computed per zip prefix in the reconciled layer; this joins the two facts on order_id — a drill-across." |
| 4:10 | materialised view | `\i demo/02_explain_mv.sql` | "Same question on the fact table and on the pre-aggregated view: hundreds of milliseconds vs a few. Physical optimisation only, the model is unchanged." |
| 4:50 | close | `\q` | "Everything is in the repository; `run_all.sh` reproduces it." |

## If something goes wrong

* Postgres not running: `brew services start postgresql@14`, wait 3 s.
* `run_all.sh` fails: skip it, the database from before the call is still there (the script drops schemas only after starting; if it failed in `00_schemas.sql`, run `scripts/run_all.sh` again).
* A query prints too much: `\pset pager off` was set; use `q` to leave the pager if it appears.
* No terminal at all: slides 10–14 contain the same tables and charts; say so and go on.

## Before the call

- [ ] `scripts/run_all.sh` once, to be sure it passes
- [ ] terminal font ≥ 18 pt, dark-on-light, window on the shared screen
- [ ] `psql` opened in a second tab with `\i demo/psqlrc` already done
- [ ] slides PDF open in the first tab
