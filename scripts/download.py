"""Fetch the UCI Online Retail II workbook.

The raw file is deliberately NOT committed: it is ~46 MB, and the dataset is
redistributed under CC BY 4.0, which is cleaner to honour by reference than by
vendoring a copy. Anyone cloning the repo runs this first.

Source: Chen, D. (2019). Online Retail II. UCI Machine Learning Repository.
        https://doi.org/10.24432/C5CG6D  -  CC BY 4.0
"""

from __future__ import annotations

import hashlib
import sys
import urllib.request
import zipfile
from pathlib import Path

URL = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
RAW = Path(__file__).resolve().parents[1] / "data" / "raw"
ARCHIVE = RAW / "online_retail_ii.zip"
EXPECTED_MIN_BYTES = 40_000_000


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    RAW.mkdir(parents=True, exist_ok=True)

    if ARCHIVE.exists():
        print(f"archive already present: {ARCHIVE.name} ({ARCHIVE.stat().st_size:,} bytes)")
    else:
        print(f"downloading {URL}")
        urllib.request.urlretrieve(URL, ARCHIVE)
        size = ARCHIVE.stat().st_size
        if size < EXPECTED_MIN_BYTES:
            # A truncated or error-page response would otherwise fail much later,
            # inside the Excel reader, with a far less obvious message.
            ARCHIVE.unlink()
            print(f"download looks truncated ({size:,} bytes); removed", file=sys.stderr)
            return 1
        print(f"saved {size:,} bytes")

    print(f"sha256 {sha256(ARCHIVE)}")

    with zipfile.ZipFile(ARCHIVE) as zf:
        for name in zf.namelist():
            target = RAW / name
            if target.exists():
                print(f"already extracted: {name}")
                continue
            print(f"extracting {name}")
            zf.extract(name, RAW)

    for f in sorted(RAW.iterdir()):
        print(f"  {f.name:<40} {f.stat().st_size:>12,} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
