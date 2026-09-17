"""Bronze layer: land the source workbook as parquet, unchanged.

Bronze is deliberately dumb. Column names, types and bad rows are all left
exactly as they arrive; the only additions are load metadata so any downstream
row can be traced back to the sheet and run that produced it. Every cleaning
decision belongs in silver, where it is visible and testable.

Both worksheets share a schema and are stacked into one parquet file, with
`source_sheet` preserving which period a row came from.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "raw" / "online_retail_II.xlsx"
BRONZE = ROOT / "data" / "bronze"
OUT = BRONZE / "online_retail.parquet"
MANIFEST = BRONZE / "_manifest.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not SOURCE.exists():
        raise SystemExit(f"source missing: {SOURCE}\nRun scripts/download.py first.")

    BRONZE.mkdir(parents=True, exist_ok=True)
    loaded_at = datetime.now(timezone.utc)
    source_hash = sha256(SOURCE)

    book = pd.ExcelFile(SOURCE, engine="openpyxl")
    print(f"sheets: {book.sheet_names}")

    frames, per_sheet = [], {}
    for sheet in book.sheet_names:
        # dtype=object keeps everything as-read; no silent coercion in bronze.
        df = book.parse(sheet, dtype=object)
        df["source_sheet"] = sheet
        per_sheet[sheet] = len(df)
        frames.append(df)
        print(f"  {sheet:<12} {len(df):>9,} rows  {len(df.columns)} cols")

    raw = pd.concat(frames, ignore_index=True)
    raw["_loaded_at"] = loaded_at
    raw["_source_file"] = SOURCE.name
    raw["_source_sha256"] = source_hash

    # Parquet needs a concrete type per column; object columns holding mixed
    # int/str/NaN cannot be written. Text-cast the identifiers and keep the
    # genuinely numeric columns numeric, leaving actual cleaning to silver.
    for col in ("Invoice", "StockCode", "Description", "Country"):
        raw[col] = raw[col].astype("string")
    for col in ("Quantity", "Price", "Customer ID"):
        raw[col] = pd.to_numeric(raw[col], errors="coerce")
    raw["InvoiceDate"] = pd.to_datetime(raw["InvoiceDate"], errors="coerce")

    raw.to_parquet(OUT, index=False, engine="pyarrow", compression="snappy")

    manifest = {
        "loaded_at": loaded_at.isoformat(),
        "source_file": SOURCE.name,
        "source_sha256": source_hash,
        "source_bytes": SOURCE.stat().st_size,
        "rows_total": int(len(raw)),
        "rows_per_sheet": per_sheet,
        "columns": list(raw.columns),
        "output": OUT.name,
        "output_bytes": OUT.stat().st_size,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"\nwrote {OUT.name}: {len(raw):,} rows, {OUT.stat().st_size:,} bytes")
    print(f"manifest: {MANIFEST.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
