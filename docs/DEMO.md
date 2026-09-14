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
| 0:40 | the three layers | `psql -d olist_dw` then `\i demo/psqlrc`, `\dt staging.*`, `\dt reconciled.*`, `\dt dw.*` (the two materialised views: `\dm dw.*`) | "Staging is the raw files, all text. Reconciled is typed and cleaned, one table per entity. dw is the star schema: six dimensions, two facts." |
| 1:20 | one data-quality trap, live | `\i demo/01_review_trap.sql` | "This order has two reviews in the file, and the customer changed the score. The reconciled layer keeps one per order, the most recent. 547 orders have two or more reviews, 202 of them with different scores." |
| 2:20 | OLAP session 05 | `\i sql/olap/05_late_delivery_vs_review.sql` (scroll to step 1) | "Delay bands: on the promised day the average review is 4.0; up to one week late it drops to 2.7 and 41 % of the reviews are one star; one to two weeks late, 71 %. Arriving two weeks early instead of a few days early changes almost nothing. Step 2: the penalty is about two stars in every region." |
| 3:20 | OLAP session 04, step 3 | `\i sql/olap/04_delivery_by_region_pair.sql` (scroll to the distance bands) | "Distance drives days, late rate and review together. The distance comes from the coordinates we computed per zip prefix in the reconciled layer; this joins the two facts on order_id — a drill-across." |
| 4:10 | materialised view | `\i demo/02_explain_mv.sql` | "Same question on the fact table and on the materialised view: about 110 ms against under 1 ms, with the same numbers. It is a physical optimisation; the model does not change." |
| 4:50 | close | `\q` | "Everything is in the repository; `run_all.sh` reproduces it." |

## If something goes wrong

* Postgres not running: `brew services start postgresql@14`, wait 3 s.
* `run_all.sh` fails: run it again, it starts from scratch (it drops and recreates the three schemas). If it fails a second time, go on with the slides.
* A query prints too much: `demo/psqlrc` turns the pager off; if a pager still appears, leave it with `q`.
* No terminal at all: slides 10–14 contain the same tables and charts; say so and go on.

## Before the call

- [ ] `scripts/run_all.sh` once, to be sure it passes
- [ ] terminal font ≥ 18 pt, dark text on a light background; share the terminal window, not the whole screen
- [ ] `psql` opened in a second tab with `\i demo/psqlrc` already done
- [ ] slides PDF open in the first tab
