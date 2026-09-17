"""Export the gold star schema to parquet for the semantic layer.

Power BI reads parquet natively, so the semantic model connects to these files
rather than to the DuckDB database. That keeps the handoff one-directional: dbt
owns the shape of the data, Power BI owns the measures, and neither reaches into
the other's territory.
"""

from __future__ import annotations

import json
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "warehouse.duckdb"
OUT = ROOT / "data" / "gold"

TABLES = ["fct_sales", "dim_customer", "dim_product", "dim_country", "dim_date"]


def main() -> int:
    if not DB.exists():
        raise SystemExit(f"warehouse missing: {DB}\nRun `dbt build` first.")

    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB), read_only=True)

    summary = {}
    for table in TABLES:
        target = OUT / f"{table}.parquet"
        con.execute(
            f"COPY (SELECT * FROM main_gold.{table}) TO '{target.as_posix()}' "
            "(FORMAT PARQUET, COMPRESSION ZSTD)"
        )
        rows = con.execute(f"SELECT count(*) FROM main_gold.{table}").fetchone()[0]
        size = target.stat().st_size
        summary[table] = {"rows": rows, "bytes": size}
        print(f"  {table:<14} {rows:>10,} rows  {size:>11,} bytes")

    (OUT / "_export.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    total = sum(v["bytes"] for v in summary.values())
    print(f"\nexported {len(TABLES)} tables, {total:,} bytes total -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
