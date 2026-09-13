"""Draw the DFM schemas and the star schema as SVG files.

DFM notation (Golfarelli & Rizzi, as taught in the course):
  * the fact is a box: name on top, measures listed below
  * dimension attributes are small circles connected by arcs; the first attribute of each
    hierarchy is attached to the fact box
  * descriptive attributes are lines ending without a circle
  * an optional arc (the attribute may be missing) is marked with a short dash across the arc
  * a shared hierarchy starts from a double circle; when the fact reaches it through several
    arcs, each arc carries the name of its role (purchase, delivered, estimated)
  * the non-additive measures are listed next to the fact with the operators they allow
    (the additivity matrix, condensed: here every non-additive measure allows AVG, MIN, MAX
    along every dimension, and all the other measures are summed)

The DFM layout is declared by hand: every attribute has its coordinates, relative to the
top-left corner of the fact box.

The star schema is read from the database catalog (tables, columns, primary and foreign keys,
row counts), so it always matches the warehouse; only the position of each table is fixed here.

Usage: uv run docs/dfm/draw_diagrams.py     -> writes docs/dfm/*.svg   (needs the olist_dw database)
"""

from __future__ import annotations

import html
import math
import os
from dataclasses import dataclass, field
from pathlib import Path

import psycopg

OUT = Path(__file__).resolve().parent

FONT = "Helvetica, Arial, sans-serif"
INK, MUTED = "#111", "#666"
FACT_FILL = "#f4e8ea"
R = 7            # radius of an attribute circle
BW = 190         # width of the fact box in the DFM


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

    def line(self, x1, y1, x2, y2, width=1.4) -> None:
        self.parts.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#222" stroke-width="{width}"/>')
        self._track(x1, y1); self._track(x2, y2)

    def polyline(self, points, width=1.4) -> None:
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
        self.parts.append(f'<polyline points="{pts}" fill="none" stroke="#222" stroke-width="{width}"/>')
        for x, y in points:
            self._track(x, y)

    def circle(self, x, y, r=R) -> None:
        self.parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#fff" stroke="#222" stroke-width="1.4"/>')
        self._track(x - r, y - r); self._track(x + r, y + r)

    def rect(self, x, y, w, h, fill="#fff", stroke="#222", width=1.4) -> None:
        self.parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')
        self._track(x, y); self._track(x + w, y + h)

    def text(self, x, y, s, anchor="middle", size=13, weight="normal", italic=False, color=INK) -> None:
        style = ' font-style="italic"' if italic else ""
        self.parts.append(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
                          f'text-anchor="{anchor}"{style} fill="{color}">{html.escape(s)}</text>')
        w = len(s) * size * 0.58                       # rough width, only to size the drawing
        x0 = {"middle": x - w / 2, "start": x, "end": x - w}[anchor]
        self._track(x0, y - size); self._track(x0 + w, y + 4)

    def save(self, path: Path, pad: int = 24) -> None:
        x0, y0 = self.minx - pad, self.miny - pad
        w, h = self.maxx - self.minx + 2 * pad, self.maxy - self.miny + 2 * pad
        body = "\n".join(self.parts)
        path.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.0f} {y0:.0f} {w:.0f} {h:.0f}" '
                        f'width="{w:.0f}" height="{h:.0f}">\n'
                        f'<rect x="{x0:.0f}" y="{y0:.0f}" width="{w:.0f}" height="{h:.0f}" fill="#fff"/>\n{body}\n</svg>\n')
        print(f"wrote {path.relative_to(OUT.parent.parent)}  ({w:.0f}x{h:.0f})")


def along(p, q, t):
    """Point at fraction t of the segment p -> q."""
    return p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])


def unit(p, q):
    """Unit vector from p towards q."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = math.hypot(dx, dy) or 1
    return dx / n, dy / n


# ----------------------------------------------------------------------------
# DFM
# ----------------------------------------------------------------------------
@dataclass
class Attr:
    name: str
    x: float
    y: float
    label: str = "above"          # where the name goes: above | below | left | right
    shared: bool = False          # first attribute of a shared hierarchy: double circle


@dataclass
class Arc:
    a: str                        # "FACT" or the name of an attribute
    b: str
    at: float | None = None       # FACT arcs only: where the arc leaves the box edge
    via: tuple[float, float] | None = None   # optional bend point
    optional: bool = False        # short dash across the arc
    role: str = ""                # role name, written over the first segment


@dataclass
class Descriptive:
    attr: str
    name: str
    x: float                      # end of the line; the name is written after it
    y: float


@dataclass
class DFM:
    name: str
    measures: list[str]
    attrs: list[Attr]
    arcs: list[Arc]
    descriptive: list[Descriptive] = field(default_factory=list)
    non_additive: list[str] = field(default_factory=list)     # measures allowing only AVG, MIN, MAX
    matrix_at: tuple[float, float] = (0, 0)                    # top-left corner of the additivity box
    min_height: int = 0


def draw_dfm(fact: DFM, path: Path) -> None:
    svg = SVG()
    bh = max(30 + 18 * len(fact.measures) + 12, fact.min_height)
    svg.rect(0, 0, BW, bh, fill=FACT_FILL)
    svg.line(0, 28, BW, 28)
    svg.text(BW / 2, 19, fact.name, weight="bold", size=16)
    for i, m in enumerate(fact.measures):
        svg.text(10, 46 + 18 * i, m, anchor="start", size=14)

    attrs = {a.name: a for a in fact.attrs}

    def leave_box(b: Attr, at: float | None) -> tuple[float, float]:
        """Point of the fact box where an arc towards attribute b starts."""
        if b.x < 0 or b.x > BW:
            return (0 if b.x < 0 else BW), (at if at is not None else min(max(b.y, 8), bh - 8))
        return (at if at is not None else min(max(b.x, 8), BW - 8)), (0 if b.y < 0 else bh)

    for arc in fact.arcs:
        b = attrs[arc.b]
        start = leave_box(b, arc.at) if arc.a == "FACT" else (attrs[arc.a].x, attrs[arc.a].y)
        points = [start] + ([arc.via] if arc.via else []) + [(b.x, b.y)]
        svg.polyline(points)
        p, q = points[0], points[1]
        length = math.hypot(q[0] - p[0], q[1] - p[1])
        ux, uy = unit(p, q)
        if arc.optional:                              # the dash across the arc
            tx, ty = along(p, q, 0.6)
            svg.line(tx - uy * 8, ty + ux * 8, tx + uy * 8, ty - ux * 8, width=1.8)
        if arc.role:                                  # role name, 42 px from the fact
            rx, ry = along(p, q, 42 / length)
            svg.text(rx, ry - 7, arc.role, size=13, italic=True)

    for d in fact.descriptive:
        a = attrs[d.attr]
        svg.line(a.x, a.y, d.x, d.y)
        right = d.x >= a.x
        svg.text(d.x + (4 if right else -4), d.y + 5, d.name, anchor="start" if right else "end", size=13)

    for a in fact.attrs:
        extra = 3 if a.shared else 0
        if a.shared:
            svg.circle(a.x, a.y, R + 3)
        svg.circle(a.x, a.y)
        lx, ly, anchor = {"above": (a.x, a.y - 13 - extra, "middle"), "below": (a.x, a.y + 25 + extra, "middle"),
                          "left": (a.x - 12 - extra, a.y + 5, "end"), "right": (a.x + 12 + extra, a.y + 5, "start")}[a.label]
        svg.text(lx, ly, a.name, anchor=anchor, size=15)

    if fact.non_additive:                             # additivity matrix, condensed
        x, y = fact.matrix_at
        w, h = 270, 30 + 17 * len(fact.non_additive) + 24
        svg.rect(x, y, w, h, stroke="#999", width=1)
        svg.text(x + 10, y + 19, "non-additive measures", anchor="start", size=13, weight="bold")
        svg.text(x + w - 10, y + 19, "any dimension", anchor="end", size=11, italic=True, color=MUTED)
        svg.line(x, y + 27, x + w, y + 27, width=0.8)
        for i, m in enumerate(fact.non_additive):
            svg.text(x + 10, y + 44 + 17 * i, m, anchor="start", size=13)
            svg.text(x + w - 10, y + 44 + 17 * i, "AVG, MIN, MAX", anchor="end", size=13)
        svg.text(x + 10, y + h - 9, "all other measures: SUM", anchor="start", size=12, italic=True, color=MUTED)
    svg.save(path)


FACT_ORDER_ITEM = DFM(
    name="ORDER ITEM",
    measures=["price", "freight value", "freight ratio", "distance (km)"],
    min_height=130,
    attrs=[
        Attr("purchase date", -70, 30, label="below"),
        Attr("month", -200, 30), Attr("quarter", -330, 30), Attr("year", -460, 30),
        Attr("day of week", -135, -15),
        Attr("customer", -70, 100),
        Attr("product", 260, 30), Attr("category", 390, 30), Attr("macro-category", 520, 30),
        Attr("seller", 260, 118, label="right"),
        # geography shared by customer and seller
        Attr("zip prefix", 95, 215, label="below", shared=True),
        Attr("city", 225, 215, label="below"), Attr("state", 355, 215, label="below"),
        Attr("region", 485, 215, label="below"),
        Attr("order status", 45, -60), Attr("order", 145, -60),
    ],
    arcs=[
        Arc("FACT", "purchase date"), Arc("purchase date", "month"), Arc("month", "quarter"),
        Arc("quarter", "year"), Arc("purchase date", "day of week"),
        Arc("FACT", "customer"), Arc("customer", "zip prefix"),
        Arc("FACT", "seller"), Arc("seller", "zip prefix"),
        Arc("zip prefix", "city"), Arc("city", "state"), Arc("state", "region"),
        Arc("FACT", "product"), Arc("product", "category"), Arc("category", "macro-category"),
        Arc("FACT", "order status"), Arc("FACT", "order"),
    ],
    descriptive=[
        Descriptive("customer", "n. orders", -108, 132),
        Descriptive("product", "weight", 300, 58), Descriptive("product", "volume", 300, 78),
        Descriptive("product", "photos", 300, 98),
        Descriptive("order", "line number", 185, -88),
    ],
    non_additive=["freight ratio", "distance (km)"],
    matrix_at=(-470, 108),
)

FACT_ORDER = DFM(
    name="ORDER",
    measures=["n. items", "n. sellers", "total price", "total freight", "total paid", "n. payments",
              "n. installments", "delivery days", "estimated days", "delay days",
              "approval hours", "carrier days", "review score"],
    attrs=[
        # one date hierarchy, shared by three roles
        Attr("date", -150, 90, label="below", shared=True),
        Attr("month", -280, 90), Attr("quarter", -410, 90), Attr("year", -540, 90),
        Attr("day of week", -215, 45),
        Attr("customer", -70, 220), Attr("zip prefix", -200, 220), Attr("city", -330, 220),
        Attr("state", -460, 220), Attr("region", -590, 220),
        Attr("order status", 260, 30), Attr("payment type", 260, 95), Attr("order", 260, 160),
    ],
    arcs=[
        Arc("FACT", "date", at=40, via=(-85, 40), role="purchase"),
        Arc("FACT", "date", at=90, role="delivered", optional=True),
        Arc("FACT", "date", at=140, via=(-85, 140), role="estimated"),
        Arc("date", "month"), Arc("month", "quarter"), Arc("quarter", "year"), Arc("date", "day of week"),
        Arc("FACT", "customer"), Arc("customer", "zip prefix"), Arc("zip prefix", "city"),
        Arc("city", "state"), Arc("state", "region"),
        Arc("FACT", "order status"), Arc("FACT", "payment type"), Arc("FACT", "order"),
    ],
    descriptive=[
        Descriptive("customer", "n. orders", -108, 252),
        Descriptive("order", "is late", 305, 190), Descriptive("order", "has review", 305, 212),
    ],
    non_additive=["n. sellers", "n. installments", "delivery days", "estimated days", "delay days",
                  "approval hours", "carrier days", "review score"],
    matrix_at=(400, 6),
)


# ----------------------------------------------------------------------------
# star schema (logical level), read from the database catalog
# ----------------------------------------------------------------------------
@dataclass
class Table:
    name: str
    columns: list[str] = field(default_factory=list)
    pk: list[str] = field(default_factory=list)
    fks: dict[str, str] = field(default_factory=dict)     # column -> referenced table
    rows: int = 0

    @property
    def fact(self) -> bool:
        return self.name.startswith("fact_")


def read_catalog(conn) -> dict[str, Table]:
    """Tables of the dw schema with their columns, keys and row counts."""
    tables: dict[str, Table] = {}
    with conn.cursor() as cur:
        cur.execute("""
            SELECT table_name, column_name FROM information_schema.columns
            WHERE table_schema = 'dw' ORDER BY table_name, ordinal_position""")
        for t, c in cur.fetchall():
            tables.setdefault(t, Table(t)).columns.append(c)
        cur.execute("""
            SELECT rel.relname, c.contype, a.attname, ref.relname
            FROM pg_constraint c
            JOIN pg_class rel     ON rel.oid = c.conrelid
            JOIN pg_namespace n   ON n.oid = rel.relnamespace AND n.nspname = 'dw'
            JOIN pg_attribute a   ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
            LEFT JOIN pg_class ref ON ref.oid = c.confrelid
            WHERE c.contype IN ('p', 'f')""")
        for t, kind, col, ref in cur.fetchall():
            if kind == "p":
                tables[t].pk.append(col)
            else:
                tables[t].fks[col] = ref
        for t in tables.values():
            cur.execute(f'SELECT count(*) FROM dw."{t.name}"')
            t.rows = cur.fetchone()[0]
    return tables


# position of the tables: columns from left to right, tables stacked top to bottom
STAR_LAYOUT = [
    ["dim_seller", "dim_product"],
    ["fact_order_item"],
    ["dim_date", "dim_customer", "dim_order_status"],
    ["dim_payment_type", "fact_order"],
]
# compact view: keys are always shown, plus these attributes; the rest is counted as "… n more"
COMPACT_ATTRS = {
    "dim_product": ["category_en", "macro_category"],
    "dim_seller": ["city", "state_code", "region_name"],
    "dim_customer": ["customer_unique_id", "city", "state_code", "region_name"],
    "dim_date": ["full_date", "day_of_week", "month", "quarter", "year"],
    "dim_order_status": ["status"],
    "dim_payment_type": ["payment_type"],
    "fact_order_item": ["price", "freight_value", "freight_ratio", "distance_km"],
    "fact_order": ["n_items", "total_price", "delivery_days", "delay_days", "review_score"],
}
TW, LH, GAP_X, GAP_Y = 250, 19, 70, 36      # table width, row height, gaps between tables


def crow_foot(svg: SVG, p, q) -> None:
    """'Many' end of a relationship, at point p on the edge of the fact, line going to q."""
    ux, uy = unit(p, q)
    tip = (p[0] + ux * 14, p[1] + uy * 14)
    for s in (-1, 0, 1):
        svg.line(tip[0], tip[1], p[0] - uy * 7 * s, p[1] + ux * 7 * s, width=1.2)


def one_mark(svg: SVG, p, q) -> None:
    """'One' end of a relationship: a bar across the line near point p (edge of the dimension)."""
    ux, uy = unit(p, q)
    m = (p[0] + ux * 9, p[1] + uy * 9)
    svg.line(m[0] - uy * 6, m[1] + ux * 6, m[0] + uy * 6, m[1] - ux * 6, width=1.2)


def draw_star(tables: dict[str, Table], path: Path, compact: bool = False) -> None:
    placed = {name for col in STAR_LAYOUT for name in col}
    assert placed == set(tables), f"tables and layout differ: {placed ^ set(tables)}"
    svg = SVG()

    shown: dict[str, list[str]] = {}
    for t in tables.values():
        if compact:
            missing = set(COMPACT_ATTRS[t.name]) - set(t.columns)
            assert not missing, f"{t.name} has no column {missing}"
            keep = set(t.pk) | set(t.fks) | set(COMPACT_ATTRS[t.name])
            cols = [c for c in t.columns if c in keep]
        else:
            cols = list(t.columns)
        hidden = len(t.columns) - len(cols)
        shown[t.name] = cols + ([f"… {hidden} more"] if hidden else [])

    height = {n: 26 + LH * len(rows) + 8 for n, rows in shown.items()}
    col_h = [sum(height[n] for n in col) + GAP_Y * (len(col) - 1) for col in STAR_LAYOUT]
    left, top = {}, {}
    for i, col in enumerate(STAR_LAYOUT):
        y = (max(col_h) - col_h[i]) / 2
        for n in col:
            left[n], top[n] = i * (TW + GAP_X), y
            y += height[n] + GAP_Y

    def row_y(table: str, column: str) -> float:
        return top[table] + 26 + LH * shown[table].index(column) + 10

    for n, rows in shown.items():
        t, x, y = tables[n], left[n], top[n]
        svg.rect(x, y, TW, height[n], fill=FACT_FILL if t.fact else "#fff")
        svg.line(x, y + 26, x + TW, y + 26)
        svg.text(x + 8, y + 18, n, anchor="start", size=15, weight="bold")
        svg.text(x + TW - 8, y + 18, f"{t.rows:,} rows", anchor="end", size=11, color=MUTED)
        for i, c in enumerate(rows):
            yy = y + 26 + LH * i + 15
            if c.startswith("…"):
                svg.text(x + 8, yy, c, anchor="start", size=13, italic=True, color=MUTED)
                continue
            svg.text(x + 8, yy, c, anchor="start", size=14, weight="bold" if c in t.pk else "normal")
            tag = "PK" if c in t.pk else "FK" if c in t.fks else ""
            if tag:
                svg.text(x + TW - 8, yy, tag, anchor="end", size=11, italic=True)

    # one line per foreign key: crow's foot on the fact (many), bar on the dimension (one)
    for f in (t for t in tables.values() if t.fact):
        by_dim: dict[str, list[str]] = {}
        for col, ref in f.fks.items():
            by_dim.setdefault(ref, []).append(col)
        for ref, cols in by_dim.items():
            cols.sort(key=shown[f.name].index)
            for k, col in enumerate(cols):
                y1 = row_y(f.name, col)
                y2 = row_y(ref, tables[ref].pk[0]) + (k - (len(cols) - 1) / 2) * 7
                fl, fr, dl, dr = left[f.name], left[f.name] + TW, left[ref], left[ref] + TW
                if dr <= fl:                          # dimension on the left
                    pts = [(fl, y1), (fl - 18, y1), (dr + 18, y2), (dr, y2)]
                elif dl >= fr:                        # dimension on the right
                    pts = [(fr, y1), (fr + 18, y1), (dl - 18, y2), (dl, y2)]
                else:                                 # same column: go round on the right
                    xo = max(fr, dr) + 24
                    pts = [(fr, y1), (xo, y1), (xo, y2), (dr, y2)]
                svg.polyline(pts, width=1.2)
                crow_foot(svg, pts[0], pts[1])
                one_mark(svg, pts[-1], pts[-2])
    svg.save(path)


if __name__ == "__main__":
    draw_dfm(FACT_ORDER_ITEM, OUT / "dfm_order_item.svg")
    draw_dfm(FACT_ORDER, OUT / "dfm_order.svg")
    with psycopg.connect(os.environ.get("DATABASE_URL", "dbname=olist_dw")) as conn:
        tables = read_catalog(conn)
    draw_star(tables, OUT / "star_schema.svg")
    draw_star(tables, OUT / "star_schema_compact.svg", compact=True)
