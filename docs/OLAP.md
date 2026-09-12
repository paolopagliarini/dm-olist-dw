# OLAP sessions

Seven analysis sessions on the star schema, one SQL file each in `sql/olap/`. Every session starts from a
business question, names the OLAP operations it uses (roll-up, drill-down, slice, dice, pivot, drill-across)
and ends with what the numbers say. All queries run on PostgreSQL 14; unless stated otherwise they are
restricted to **delivered** orders (96,478 of 99,441). Revenue = sum of item prices (freight excluded), in BRL.

Run one session with `psql -d olist_dw -f sql/olap/05_late_delivery_vs_review.sql`.

| # | Session | Question | Main operations | Facts used |
|---|---|---|---|---|
| 01 | Revenue by product hierarchy | Where does the money come from? | roll-up (ROLLUP), drill-down | fact_order_item |
| 02 | Revenue by geography | How concentrated is demand? | roll-up / drill-down (GROUPING SETS) | fact_order_item |
| 03 | Seasonality | Is there a seasonal pattern? | slice, pivot, drill-down to day | fact_order |
| 04 | Delivery across regions | How does distance affect delivery? | dice, drill-across | fact_order + fact_order_item |
| 05 | Late delivery and reviews | Does lateness change the review? | slice, bucketing, dice | fact_order |
| 06 | Freight burden | When does shipping cost as much as the item? | dice, CUBE | fact_order_item |
| 07 | Seller concentration | How many sellers make the revenue? | window functions, dice | fact_order_item |

---

## 01 — Revenue along the product hierarchy

**Question.** Where does the money come from, and how concentrated is it across product lines?

**Operations.** Roll-up `category → macro-category → total` with `GROUP BY ROLLUP`; `GROUPING()` labels the
level of each row. Then drill-down into the largest macro-category, split by year with `FILTER`.

**Result (roll-up, top level).** Total delivered revenue R$ 13.22 M on 110,197 order lines.

| macro-category | lines | revenue | share |
|---|---:|---:|---:|
| Home & Furniture | 29,005 | 2,821,271 | 21.3 % |
| Sports & Leisure | 17,022 | 2,233,862 | 16.9 % |
| Electronics & Computers | 16,869 | 1,841,712 | 13.9 % |
| Health & Beauty | 12,805 | 1,623,276 | 12.3 % |
| Fashion & Accessories | 9,511 | 1,502,217 | 11.4 % |
| … 7 more | | | 24.2 % |

**Drill-down (Home & Furniture).** Three categories make 83 % of it: `bed_bath_table` (1.02 M),
`furniture_decor` (0.71 M), `housewares` (0.62 M). `housewares` grew most between 2017 and 2018 (+76 %).

**Reading.** Five macro-categories cover three quarters of revenue. The top level is useful because the 73
raw categories are too fragmented to compare (Olist even has near-duplicates such as `home_confort` and
`home_comfort_2`).

---

## 02 — Revenue along the customer geography

**Question.** How is demand distributed across Brazil?

**Operations.** `GROUPING SETS ((region), (region, state))` gives the two levels in one pass, each with its
share computed by a window function partitioned on the grouping level. Then drill-down to the cities of São Paulo.

**Result.**

| region | orders | revenue | share | revenue / order | freight as % of price |
|---|---:|---:|---:|---:|---:|
| Southeast | 66,204 | 8,650,036 | 65.4 % | 130.66 | 15.2 % |
| South | 13,813 | 1,900,796 | 14.4 % | 137.61 | 17.7 % |
| Northeast | 9,045 | 1,497,114 | 11.3 % | 165.52 | 21.7 % |
| Central-West | 5,619 | 846,358 | 6.4 % | 150.62 | 17.6 % |
| North | 1,797 | 327,194 | 2.5 % | 182.08 | 22.7 % |

The state of São Paulo alone is 38.3 % of national revenue; the city of São Paulo is 36.7 % of the state.

**Reading.** Demand is where the sellers are (74 % of sellers are in the Southeast, see session 04). The
further from the Southeast, the bigger the average order and the heavier the freight: customers in the North
and Northeast pay 22–23 % of the item price in shipping against 14 % in São Paulo.

---

## 03 — Seasonality of sales

**Question.** How do sales evolve over time, and is there a seasonal peak?

**Operations.** Slice on the time dimension to the months that exist in both years (Jan–Aug 2017 and 2018;
Sept–Dec 2016 and Sept–Oct 2018 are almost empty in the dataset and are excluded on purpose). Pivot
month × year with `FILTER`, month-over-month growth with `LAG`, then drill-down to the day.

**Result.**
- Monthly orders grow from 750 (Jan 2017) to ~7,000 (Jan 2018) and then **plateau at 6,000–7,000 per month**
  through 2018. Year-over-year growth falls from +727 % (January) to +51 % (August): the marketplace matured.
- November 2017 is the peak: +52 % over October, 7,289 orders, R$ 988 k.
- Drill-down to the day: **Black Friday, 24 November 2017, 1,176 orders** — 2.4× the next busiest day, and the
  four following days are the other four busiest days of the whole dataset.

**Reading.** One event dominates the seasonality; December drops back by 26 %. Any comparison across years
must exclude the partial months, which is why the time dimension carries `year_month` as an explicit label.

---

## 04 — Delivery performance across the country

**Question.** How long does delivery take, and how often is it late, depending on where seller and customer are?

**Operations.** Dice seller region × customer region. This needs a **drill-across**: delivery measures live
in `fact_order`, the seller and the distance in `fact_order_item`; the two facts are joined on `order_id`
(restricted to single-seller orders, 98.7 % of them, so that "the seller of the order" is well defined).
Then the same cube cut by distance band.

**Result.**
- Sellers are concentrated: 73.9 % in the Southeast, 21.6 % in the South, **5 sellers in the whole North**.
- Same-region deliveries take 9–11 days; Southeast → North takes 22.6 days over 2,238 km on average.
- By distance band: < 100 km → 6.5 days, 4.5 % late, review 4.29; > 2000 km → 21.2 days, 12.1 % late, review 3.99.
- The promised date is always about twice the actual time (e.g. 21 promised vs 10 actual days within the
  Southeast): Olist promises conservatively, which keeps the late rate under 13 % even for the North.

**Reading.** Distance explains delivery time, late rate and review score together, monotonically. This is the
session that justifies computing `distance_km` in the reconciled layer.

---

## 05 — Late deliveries and customer reviews

**Question.** Does a late delivery change what customers think? By how much? Everywhere?

**Operations.** Slice to delivered orders with a review; bucket `delay_days` (delivered − promised date);
dice by customer region; then by quarter.

**Result.**

| delay band | orders | avg review | 1-star | 5-star |
|---|---:|---:|---:|---:|
| 2+ weeks early | 41,861 (43.7 %) | 4.32 | 6.6 % | 64.4 % |
| early | 46,302 (48.3 %) | 4.27 | 6.6 % | 60.7 % |
| on the promised day | 1,280 (1.3 %) | 4.03 | 8.5 % | 50.6 % |
| up to 1 week late | 3,600 (3.8 %) | **2.71** | 41.4 % | 23.9 % |
| 1–2 weeks late | 1,446 (1.5 %) | **1.67** | 70.6 % | 6.8 % |
| more than 2 weeks late | 1,335 (1.4 %) | 1.72 | 69.0 % | 7.2 % |

- The penalty is the same everywhere: on-time vs late ≈ **2.0 stars** in every region (1.93–2.07), even
  though the late rate differs (5.8 % South, 12.5 % Northeast).
- By quarter: 2018-Q1 is the worst quarter (12.7 % late, review 3.94) — the backlog after Black Friday and
  Christmas; by 2018-Q3 delivery is at 8.2 days and the review at 4.31.

**Reading.** Being early earns nothing (4.27 vs 4.32); being one day late costs 1.3 stars; one week late and
the modal review is one star. The review is driven by the promise being kept, not by the absolute delivery time.

---

## 06 — The weight of shipping costs

**Question.** For which products, and at which distances, does shipping cost as much as the item?

**Operations.** Dice macro-category × distance band on `fact_order_item`; `CUBE` gives all the marginals in
one query; `freight_ratio = freight / price` per line.

**Result.**
- Freight is 17.6 % of revenue overall; 12.7 % under 100 km, 21.6 % over 1000 km.
- By macro-category: Food & Drink 25.9 % and **Home & Furniture 22.2 %** (31.5 % over 1000 km — bulky items);
  Fashion 11.2 % and Appliances 10.5 % (high prices).
- Electronics & Computers has the highest share of lines where **shipping ≥ price: 7.9 %** (cheap accessories).

**Reading.** Shipping cost depends on both what is shipped and how far: the cube shows the two effects
adding up (Home & Furniture over 1000 km = 31.5 %).

---

## 07 — Seller concentration

**Question.** How many sellers make most of the revenue, and does it differ by macro-category?

**Operations.** Ranking and cumulative share with window functions (`rank()`, `sum() OVER (ORDER BY …)`);
dice by macro-category for the share of the top 3 sellers.

**Result.**
- 2,970 sellers with delivered sales. **127 sellers (4.3 %) make 50 % of revenue; 533 (18 %) make 80 %.**
  The top 100 sellers (3.4 %) make 45.5 %.
- The biggest seller has 1.72 % of revenue (Fashion, Guariba SP); 9 of the top 10 are in São Paulo state.
- Concentration is highest in Fashion & Accessories (top 3 sellers = 36.5 %) and lowest in Sports & Leisure
  (12.8 %, 858 sellers).

**Reading.** A long tail typical of marketplaces. Nothing here required a special structure: the star schema
plus window functions answers it directly.

---

## Materialised views

`sql/50_dw_materialized_views.sql` pre-aggregates the two most used cubes:

| view | rows | base query | on the view |
|---|---:|---:|---:|
| `mv_monthly_sales` (month × product hierarchy × customer state × status) | 13,417 | 270–1,900 ms | 4 ms |
| `mv_delivery_by_region_pair` (seller region × customer region × year) | 56 | 340 ms | < 1 ms |

Measured with `EXPLAIN (ANALYZE)`; the base query scans the 112,650 lines of `fact_order_item` and sorts
them, the view is read from an index. The views are a physical optimisation only: the OLAP files above are
written against the base star schema so that every number can be traced back to the facts.
