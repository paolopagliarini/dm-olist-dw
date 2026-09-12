"""Draw the DFM schemas and the star schema as SVG files.

DFM notation (Golfarelli & Rizzi, as taught in the course):
  * the fact is a box: name on top, measures listed below
  * dimension attributes are small circles, connected by lines; the first one of each
    hierarchy is attached to the fact box
  * descriptive attributes are lines ending without a circle
  * an optional arc (attribute that may be missing) is marked with a short dash across the line

The layout is declared by hand for each diagram (which side of the fact each hierarchy leaves
from, and in which row/column), the script only computes coordinates and writes the SVG.

Usage: uv run docs/dfm/draw_diagrams.py     -> writes docs/dfm/*.svg
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

OUT = Path(__file__).resolve().parent

FONT = "Helvetica, Arial, sans-serif"
R = 7            # radius of a dimension-attribute circle
STEP = 118       # distance between two levels of a hierarchy (horizontal chains)
VSTEP = 62       # distance between two levels (vertical chains)
ROW_GAP = 58     # vertical gap between two hierarchies on the same side


# ----------------------------------------------------------------------------
# generic SVG helpers
# ----------------------------------------------------------------------------
class SVG:
    def __init__(self) -> None:
        self.parts: list[str] = []
        self.minx = self.miny = 10**9
        self.maxx = self.maxy = -(10**9)

    def _track(self, x: float, y: float) -> None:
        self.minx, self.maxx = min(self.minx, x), max(self.maxx, x)
        self.miny, self.maxy = min(self.miny, y), max(self.maxy, y)

    def line(self, x1, y1, x2, y2, dashed=False) -> None:
        dash = ' stroke-dasharray="6 4"' if dashed else ""
        self.parts.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="#222" stroke-width="1.4"{dash}/>')
        self._track(x1, y1); self._track(x2, y2)

    def circle(self, x, y, r=R) -> None:
        self.parts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="#fff" stroke="#222" stroke-width="1.4"/>')
        self._track(x - r, y - r); self._track(x + r, y + r)

    def text(self, x, y, s, anchor="middle", size=13, weight="normal", italic=False) -> None:
        style = f' font-style="italic"' if italic else ""
        self.parts.append(f'<text x="{x:.0f}" y="{y:.0f}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}"{style} fill="#111">{s}</text>')
        w = len(s) * size * 0.58
        if anchor == "middle":
            self._track(x - w / 2, y - size); self._track(x + w / 2, y + 4)
        elif anchor == "start":
            self._track(x, y - size); self._track(x + w, y + 4)
        else:
            self._track(x - w, y - size); self._track(x, y + 4)

    def rect(self, x, y, w, h, fill="#fff") -> None:
        self.parts.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" fill="{fill}" stroke="#222" stroke-width="1.6"/>')
        self._track(x, y); self._track(x + w, y + h)

    def save(self, path: Path, pad=24) -> None:
        w = self.maxx - self.minx + 2 * pad
        h = self.maxy - self.miny + 2 * pad
        body = "\n".join(self.parts)
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{self.minx - pad:.0f} {self.miny - pad:.0f} {w:.0f} {h:.0f}" '
               f'width="{w:.0f}" height="{h:.0f}">\n<rect x="{self.minx - pad:.0f}" y="{self.miny - pad:.0f}" width="{w:.0f}" height="{h:.0f}" fill="#fff"/>\n{body}\n</svg>\n')
        path.write_text(svg)
        print(f"wrote {path.relative_to(OUT.parent.parent)}  ({w:.0f}x{h:.0f})")


# ----------------------------------------------------------------------------
# DFM
# ----------------------------------------------------------------------------
@dataclass
class Hierarchy:
    side: str                         # 'left' | 'right' | 'top' | 'bottom'
    slot: int                         # row (left/right) or column (top/bottom), 0 = first
    levels: list[str]                 # dimension attributes, from the finest (attached to the fact) outward
    descriptive: dict[str, list[str]] = field(default_factory=dict)   # level -> descriptive attributes
    optional: bool = False            # optional arc between the fact and the first level
    branches: dict[str, list[str]] = field(default_factory=dict)      # level -> extra chain leaving sideways


@dataclass
class Fact:
    name: str
    measures: list[str]
    hierarchies: list[Hierarchy]


def draw_dfm(fact: Fact, path: Path) -> None:
    svg = SVG()
    # fact box
    bw = 190
    side_rows = 1 + max([h.slot for h in fact.hierarchies if h.side in ("left", "right")] or [0])
    bh = max(30 + 18 * len(fact.measures) + 10, 20 + ROW_GAP * (side_rows - 1) + 30)
    bx, by = 0, 0                      # top-left; everything is relative, the viewBox is fitted at the end
    svg.rect(bx, by, bw, bh, fill="#f3f3f3")
    svg.line(bx, by + 28, bx + bw, by + 28)
    svg.text(bx + bw / 2, by + 19, fact.name, weight="bold", size=14)
    for i, m in enumerate(fact.measures):
        svg.text(bx + 10, by + 46 + 18 * i, m, anchor="start", size=12)

    cx, cy = bx + bw / 2, by + bh / 2

    for h in fact.hierarchies:
        if h.side in ("left", "right"):
            direction = -1 if h.side == "left" else 1
            y = by + 20 + h.slot * ROW_GAP
            x0 = bx if h.side == "left" else bx + bw
            x = x0 + direction * 60
            svg.line(x0, y, x, y, dashed=h.optional)
            prev = (x, y)
            for li, level in enumerate(h.levels):
                if li > 0:
                    x = prev[0] + direction * STEP
                    svg.line(prev[0], y, x, y)
                svg.circle(x, y)
                svg.text(x, y - 13, level, size=12)
                for di, d in enumerate(h.descriptive.get(level, [])):
                    # descriptive attribute: short line downwards, label at the end, no circle
                    dy = y + 22 + 16 * di
                    svg.line(x, y + R, x, dy)
                    svg.text(x + 5, dy + 4, d, anchor="start", size=11, italic=True)
                for br in h.branches.get(level, []):
                    # side branch: one extra level drawn diagonally upwards
                    bxx, byy = x + direction * 70, y - 40
                    svg.line(x, y, bxx, byy)
                    svg.circle(bxx, byy)
                    svg.text(bxx, byy - 13, br, size=12)
                prev = (x, y)
        else:
            direction = -1 if h.side == "top" else 1
            x = bx + 30 + h.slot * 150
            y0 = by if h.side == "top" else by + bh
            y = y0 + direction * 45
            svg.line(x, y0, x, y, dashed=h.optional)
            prev = (x, y)
            for li, level in enumerate(h.levels):
                if li > 0:
                    y = prev[1] + direction * VSTEP
                    svg.line(x, prev[1], x, y)
                svg.circle(x, y)
                svg.text(x + 12, y + 4, level, anchor="start", size=12)
                for di, d in enumerate(h.descriptive.get(level, [])):
                    dx = x - 22 - 0 * di
                    svg.line(x - R, y, dx, y + 14 * (di + 1))
                    svg.text(dx - 4, y + 14 * (di + 1) + 4, d, anchor="end", size=11, italic=True)
                for br in h.branches.get(level, []):
                    bxx, byy = x - 70, y + direction * 40
                    svg.line(x, y, bxx, byy)
                    svg.circle(bxx, byy)
                    svg.text(bxx - 12, byy + 4, br, anchor="end", size=12)
                prev = (x, y)
    svg.save(path)


DATE = ["date", "month", "quarter", "year"]
GEO_C = ["customer", "zip prefix", "city", "state", "region"]
GEO_S = ["seller", "zip prefix", "city", "state", "region"]

FACT_ORDER_ITEM = Fact(
    name="ORDER ITEM",
    measures=["price", "freight value", "freight ratio", "distance (km)"],
    hierarchies=[
        Hierarchy("left", 0, ["purchase date"] + DATE[1:], branches={"purchase date": ["day of week"]}),
        Hierarchy("left", 1, GEO_C, descriptive={"customer": ["n. orders"]}),
        Hierarchy("right", 0, ["product", "category", "macro-category"],
                  descriptive={"product": ["weight", "volume", "photos"]}),
        Hierarchy("right", 2, GEO_S),
        Hierarchy("bottom", 0, ["order status"]),
        Hierarchy("bottom", 1, ["order"], descriptive={"order": ["line number"]}),
    ],
)

FACT_ORDER = Fact(
    name="ORDER",
    measures=["n. items", "n. sellers", "total price", "total freight", "total paid",
              "n. installments", "delivery days", "estimated days", "delay days",
              "approval hours", "carrier days", "review score"],
    hierarchies=[
        Hierarchy("left", 0, ["purchase date"] + DATE[1:], branches={"purchase date": ["day of week"]}),
        Hierarchy("left", 1, ["delivered date"] + DATE[1:], optional=True),
        Hierarchy("left", 2, ["estimated date"] + DATE[1:]),
        Hierarchy("left", 3, GEO_C, descriptive={"customer": ["n. orders"]}),
        Hierarchy("right", 0, ["order status"]),
        Hierarchy("right", 1, ["payment type"]),
        Hierarchy("right", 2, ["order"], descriptive={"order": ["is late", "has review"]}),
    ],
)


# ----------------------------------------------------------------------------
# star schema (logical level): tables with their columns, FK lines
# ----------------------------------------------------------------------------
@dataclass
class Table:
    name: str
    x: int
    y: int
    columns: list[str]                # 'PK name', 'FK name' or plain name
    fact: bool = False


def draw_star(path: Path) -> None:
    svg = SVG()
    W, LH = 210, 15
    tables = {
        "dim_product": Table("dim_product", 0, 40, ["PK product_key", "product_id", "category_pt", "category_en",
                                                    "macro_category", "weight_g", "volume_cm3", "photos_qty"]),
        "dim_seller": Table("dim_seller", 0, 480, ["PK seller_key", "seller_id", "zip_prefix", "city",
                                                   "state_code", "state_name", "region_name", "lat", "lng"]),
        "fact_order_item": Table("fact_order_item", 280, 250,
                                 ["PK order_id", "PK order_item_id", "FK purchase_date_key", "FK customer_key",
                                  "FK seller_key", "FK product_key", "FK status_key",
                                  "price", "freight_value", "freight_ratio", "distance_km"], fact=True),
        "dim_date": Table("dim_date", 560, 0, ["PK date_key", "full_date", "day", "day_of_week", "week_of_year",
                                               "month", "month_name", "year_month", "quarter", "year_quarter", "year"]),
        "dim_customer": Table("dim_customer", 560, 310, ["PK customer_key", "customer_unique_id", "zip_prefix", "city",
                                                         "state_code", "state_name", "region_name", "lat", "lng", "n_orders"]),
        "dim_order_status": Table("dim_order_status", 560, 600, ["PK status_key", "status"]),
        "fact_order": Table("fact_order", 840, 200,
                            ["PK order_id", "FK purchase_date_key", "FK delivered_date_key", "FK estimated_date_key",
                             "FK customer_key", "FK status_key", "FK payment_type_key",
                             "n_items", "n_sellers", "total_price", "total_freight", "total_paid",
                             "n_payments", "n_installments", "delivery_days", "estimated_days", "delay_days",
                             "is_late", "approval_hours", "carrier_days", "review_score", "has_review"], fact=True),
        "dim_payment_type": Table("dim_payment_type", 1120, 60, ["PK payment_type_key", "payment_type"]),
    }
    for t in tables.values():
        h = 26 + LH * len(t.columns) + 8
        svg.rect(t.x, t.y, W, h, fill="#e9eef7" if t.fact else "#fff")
        svg.line(t.x, t.y + 24, t.x + W, t.y + 24)
        svg.text(t.x + W / 2, t.y + 17, t.name, weight="bold", size=13)
        for i, c in enumerate(t.columns):
            tag, name = (c.split(" ", 1) if c.startswith(("PK ", "FK ")) else ("", c))
            svg.text(t.x + 8, t.y + 38 + LH * i, name, anchor="start", size=11, weight="bold" if tag == "PK" else "normal")
            if tag:
                svg.text(t.x + W - 8, t.y + 38 + LH * i, tag, anchor="end", size=9, italic=True)

    def mid(t: Table, side: str):
        h = 26 + LH * len(t.columns) + 8
        return {"l": (t.x, t.y + h / 2), "r": (t.x + W, t.y + h / 2), "t": (t.x + W / 2, t.y), "b": (t.x + W / 2, t.y + h),
                "tr": (t.x + W, t.y), "tl": (t.x, t.y)}[side]

    links = [("fact_order_item", "l", "dim_product", "r"), ("fact_order_item", "l", "dim_seller", "r"),
             ("fact_order_item", "t", "dim_date", "l"), ("fact_order_item", "r", "dim_customer", "l"),
             ("fact_order_item", "b", "dim_order_status", "l"),
             ("fact_order", "l", "dim_date", "r"), ("fact_order", "l", "dim_customer", "r"),
             ("fact_order", "l", "dim_order_status", "r"), ("fact_order", "r", "dim_payment_type", "l"),
             ("fact_order_item", "tr", "fact_order", "tl")]
    for a, sa, b, sb in links:
        (x1, y1), (x2, y2) = mid(tables[a], sa), mid(tables[b], sb)
        svg.line(x1, y1, x2, y2, dashed=(a == "fact_order_item" and b == "fact_order"))
    svg.text(665, 250, "drill-across on order_id", size=10, italic=True)
    svg.save(path)


if __name__ == "__main__":
    draw_dfm(FACT_ORDER_ITEM, OUT / "dfm_order_item.svg")
    draw_dfm(FACT_ORDER, OUT / "dfm_order.svg")
    draw_star(OUT / "star_schema.svg")
