"""Three charts for the slides, drawn from the warehouse with matplotlib.

Usage: uv run scripts/make_charts.py      -> docs/slides/img/*.png
Env:   DATABASE_URL (default dbname=olist_dw)
"""

import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import psycopg

OUT = Path(__file__).resolve().parent.parent / "docs" / "slides" / "img"
OUT.mkdir(parents=True, exist_ok=True)
ACCENT, GREY, RED = "#1f4e79", "#9aa5b1", "#b23a3a"

plt.rcParams.update({"font.family": "Helvetica", "font.size": 11, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.grid": True, "grid.alpha": 0.25, "axes.grid.axis": "y"})


def rows(cur, sql):
    cur.execute(sql)
    return cur.fetchall()


def monthly_orders(cur):
    data = rows(cur, """
        SELECT d.year_month, count(*)
        FROM dw.fact_order o JOIN dw.dim_date d ON d.date_key = o.purchase_date_key
        JOIN dw.dim_order_status s USING (status_key)
        WHERE s.status = 'delivered' AND d.year_month BETWEEN '2017-01' AND '2018-08'
        GROUP BY 1 ORDER BY 1""")
    labels = [r[0] for r in data]
    values = [r[1] for r in data]
    colors = [RED if l == "2017-11" else ACCENT for l in labels]
    fig, ax = plt.subplots(figsize=(8, 3.6), dpi=200)
    ax.bar(labels, values, color=colors, width=0.75)
    ax.set_ylabel("delivered orders per month")
    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels([l if l.endswith(("-01", "-04", "-07", "-10")) else "" for l in labels])
    ax.annotate("Nov 2017: Black Friday", xy=(labels.index("2017-11"), 7289), xytext=(labels.index("2017-11") - 6.5, 7500),
                arrowprops=dict(arrowstyle="->", color=RED), color=RED, fontsize=10)
    fig.tight_layout()
    fig.savefig(OUT / "monthly_orders.png")


def review_by_delay(cur):
    data = rows(cur, """
        SELECT CASE WHEN o.delay_days <= -14 THEN '2+ weeks early' WHEN o.delay_days < 0 THEN 'early'
                    WHEN o.delay_days = 0 THEN 'on the day' WHEN o.delay_days <= 7 THEN '≤ 1 week late'
                    WHEN o.delay_days <= 14 THEN '1–2 weeks late' ELSE '> 2 weeks late' END AS band,
               min(o.delay_days), avg(o.review_score), 100.0 * avg((o.review_score = 1)::INT)
        FROM dw.fact_order o JOIN dw.dim_order_status s USING (status_key)
        WHERE s.status = 'delivered' AND o.has_review AND o.delay_days IS NOT NULL
        GROUP BY 1 ORDER BY 2""")
    labels = [r[0] for r in data]
    avg = [float(r[2]) for r in data]
    one_star = [float(r[3]) for r in data]
    fig, ax = plt.subplots(figsize=(8, 3.6), dpi=200)
    bars = ax.bar(labels, avg, color=[ACCENT if a >= 4 else RED for a in avg], width=0.65)
    for b, a, o in zip(bars, avg, one_star):
        ax.text(b.get_x() + b.get_width() / 2, a + 0.08, f"{a:.2f}", ha="center", fontsize=10)
        ax.text(b.get_x() + b.get_width() / 2, 0.25, f"{o:.0f}% one-star", ha="center", fontsize=9, color="white")
    ax.set_ylim(0, 5)
    ax.set_ylabel("average review score (1–5)")
    ax.set_xlabel("delivered date vs promised date")
    fig.tight_layout()
    fig.savefig(OUT / "review_by_delay.png")


def freight_by_distance(cur):
    cats = ["Home & Furniture", "Sports & Leisure", "Health & Beauty", "Electronics & Computers"]
    cur.execute("""
        SELECT p.macro_category,
               CASE WHEN f.distance_km < 100 THEN '< 100 km' WHEN f.distance_km < 500 THEN '100–500 km'
                    WHEN f.distance_km < 1000 THEN '500–1000 km' ELSE '> 1000 km' END AS band,
               min(f.distance_km), 100.0 * sum(f.freight_value) / sum(f.price)
        FROM dw.fact_order_item f JOIN dw.dim_product p USING (product_key) JOIN dw.dim_order_status s USING (status_key)
        WHERE s.status = 'delivered' AND f.distance_km IS NOT NULL AND p.macro_category = ANY(%s)
        GROUP BY 1, 2 ORDER BY 1, 3""", (cats,))
    data = cur.fetchall()
    bands = ["< 100 km", "100–500 km", "500–1000 km", "> 1000 km"]
    series = {c: [next(float(r[3]) for r in data if r[0] == c and r[1] == b) for b in bands] for c in cats}
    fig, ax = plt.subplots(figsize=(8, 3.6), dpi=200)
    w = 0.2
    palette = [ACCENT, "#4f81bd", GREY, "#c9d3dd"]
    for i, c in enumerate(cats):
        ax.bar([x + (i - 1.5) * w for x in range(len(bands))], series[c], width=w, label=c, color=palette[i])
    ax.set_xticks(range(len(bands)))
    ax.set_xticklabels(bands)
    ax.set_ylabel("freight as % of item price")
    ax.set_xlabel("distance from seller to customer")
    ax.legend(frameon=False, fontsize=9, ncol=2)
    fig.tight_layout()
    fig.savefig(OUT / "freight_by_distance.png")


if __name__ == "__main__":
    with psycopg.connect(os.environ.get("DATABASE_URL", "dbname=olist_dw")) as conn, conn.cursor() as cur:
        monthly_orders(cur)
        review_by_delay(cur)
        freight_by_distance(cur)
    print("charts written to", OUT)
