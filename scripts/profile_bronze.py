"""Profile the bronze layer and independently verify it against the source.

Two jobs:

1.  Verification. Row counts are re-read straight from the workbook's own
    worksheet dimensions rather than reusing the ingest's numbers, so this is a
    genuine second opinion rather than an echo.
2.  Profiling. Establishes the data-quality facts that silver has to deal with
    (cancellations, returns, missing customers, non-product stock codes) and
    writes them to docs/ so the README can quote real figures.
"""

from __future__ import annotations

import json
from pathlib import Path

import duckdb
import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "raw" / "online_retail_II.xlsx"
BRONZE = ROOT / "data" / "bronze" / "online_retail.parquet"
DOCS = ROOT / "docs"
OUT = DOCS / "bronze-profile.json"


def source_row_counts() -> dict[str, int]:
    """Row counts read from worksheet dimensions, minus the header row."""
    wb = openpyxl.load_workbook(SOURCE, read_only=True)
    counts = {ws.title: max(ws.max_row - 1, 0) for ws in wb.worksheets}
    wb.close()
    return counts


def main() -> int:
    DOCS.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    con.execute(f"CREATE VIEW bronze AS SELECT * FROM read_parquet('{BRONZE.as_posix()}')")
    q = lambda sql: con.execute(sql).fetchall()

    expected = source_row_counts()
    actual = dict(q("SELECT source_sheet, count(*) FROM bronze GROUP BY 1 ORDER BY 1"))
    reconciles = expected == actual

    print("row-count reconciliation")
    for sheet in sorted(expected):
        got = actual.get(sheet, 0)
        flag = "OK" if got == expected[sheet] else "MISMATCH"
        print(f"  {sheet:<16} workbook {expected[sheet]:>9,}   parquet {got:>9,}   {flag}")

    total = q("SELECT count(*) FROM bronze")[0][0]
    stats = dict(q("""
        SELECT metric, value FROM (
          SELECT 'rows'                 AS metric, count(*)::BIGINT                                        AS value FROM bronze
          UNION ALL SELECT 'cancellations',        count(*) FILTER (WHERE Invoice LIKE 'C%')                FROM bronze
          UNION ALL SELECT 'negative_quantity',    count(*) FILTER (WHERE Quantity < 0)                     FROM bronze
          UNION ALL SELECT 'zero_or_neg_price',    count(*) FILTER (WHERE Price <= 0)                       FROM bronze
          UNION ALL SELECT 'missing_customer',     count(*) FILTER (WHERE "Customer ID" IS NULL)            FROM bronze
          UNION ALL SELECT 'missing_description',  count(*) FILTER (WHERE Description IS NULL)              FROM bronze
          UNION ALL SELECT 'distinct_invoices',    count(DISTINCT Invoice)                                  FROM bronze
          UNION ALL SELECT 'distinct_stockcodes',  count(DISTINCT StockCode)                                FROM bronze
          UNION ALL SELECT 'distinct_customers',   count(DISTINCT "Customer ID")                            FROM bronze
          UNION ALL SELECT 'distinct_countries',   count(DISTINCT Country)                                  FROM bronze
        )
    """))

    date_min, date_max = q("SELECT min(InvoiceDate), max(InvoiceDate) FROM bronze")[0]

    # Stock codes that are not products at all - postage, samples, bank charges.
    non_product = q("""
        SELECT StockCode, count(*) AS n
        FROM bronze
        WHERE StockCode IS NULL OR NOT regexp_matches(StockCode, '^[0-9]{5}')
        GROUP BY 1 ORDER BY n DESC LIMIT 12
    """)

    print("\nprofile")
    for k, v in stats.items():
        pct = f"  ({v / total:.1%})" if k not in {"rows"} and not k.startswith("distinct") else ""
        print(f"  {k:<22} {v:>10,}{pct}")
    print(f"  {'date_range':<22} {date_min} -> {date_max}")

    print("\nnon-product stock codes (top 12)")
    for code, n in non_product:
        print(f"  {str(code):<20} {n:>8,}")

    OUT.write_text(json.dumps({
        "reconciles": reconciles,
        "rows_by_sheet": {"workbook": expected, "parquet": actual},
        "stats": {k: int(v) for k, v in stats.items()},
        "date_range": [str(date_min), str(date_max)],
        "non_product_stock_codes": [{"stock_code": c, "rows": int(n)} for c, n in non_product],
    }, indent=2), encoding="utf-8")

    print(f"\nwrote {OUT.relative_to(ROOT)}")
    if not reconciles:
        print("RECONCILIATION FAILED", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
