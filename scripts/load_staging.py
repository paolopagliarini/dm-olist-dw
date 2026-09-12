"""Load the raw Olist CSV files into the `staging` schema.

Every CSV becomes one table with the same columns, all of type TEXT: no parsing, no
cleaning, no assumptions. Typing, cleaning and integration happen later, in SQL, in the
reconciled layer (sql/2*.sql). Keeping the raw data untouched makes every transformation
visible and re-runnable.

Usage:  uv run scripts/load_staging.py
Env:    DATABASE_URL (default: dbname=olist_dw on the local socket)
"""

import csv
import os
import sys
from pathlib import Path

import psycopg

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
DATABASE_URL = os.environ.get("DATABASE_URL", "dbname=olist_dw")

# csv file -> staging table name
FILES = {
    "olist_customers_dataset.csv": "customers",
    "olist_geolocation_dataset.csv": "geolocation",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_orders_dataset.csv": "orders",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "product_category_name_translation.csv": "product_category_translation",
}


def read_header(path: Path) -> list[str]:
    with path.open(newline="", encoding="utf-8") as f:
        return next(csv.reader(f))


def load_file(cur: psycopg.Cursor, path: Path, table: str) -> int:
    columns = read_header(path)
    col_defs = ", ".join(f'"{c}" TEXT' for c in columns)
    cur.execute(f"DROP TABLE IF EXISTS staging.{table}")
    cur.execute(f"CREATE TABLE staging.{table} ({col_defs})")
    with path.open("rb") as f, cur.copy(
        f"COPY staging.{table} FROM STDIN WITH (FORMAT csv, HEADER true)"
    ) as copy:
        while chunk := f.read(1 << 20):
            copy.write(chunk)
    cur.execute(f"SELECT count(*) FROM staging.{table}")
    return cur.fetchone()[0]


def main() -> None:
    missing = [f for f in FILES if not (RAW_DIR / f).exists()]
    if missing:
        sys.exit(f"missing raw files in {RAW_DIR}: {missing} (run scripts/download_data.sh)")
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for filename, table in FILES.items():
            n = load_file(cur, RAW_DIR / filename, table)
            print(f"staging.{table:32s} {n:>10,} rows")
        conn.commit()


if __name__ == "__main__":
    main()
