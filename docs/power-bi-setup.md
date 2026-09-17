# Power BI setup — building the semantic layer

One-time setup to put a semantic model on top of the gold star schema. Everything
after this — relationships, measures, the calculation group, RLS — is authored as
TMDL in source control, not clicked together in the UI.

**Prerequisite:** `python scripts/export_gold.py` has been run, so
`data/gold/` holds five parquet files.

---

## Step 1 — Enable Power BI Project (.pbip) save

`File → Options and settings → Options → Preview features`

Tick **"Power BI Project (.pbip) save option"**, then restart Power BI Desktop.

On recent versions this has graduated out of preview and instead lives at
`Options → Project files` with the storage format already set to PBIP. If you see
that instead, nothing to change.

> **Why this matters.** A `.pbix` is a binary blob — git cannot diff it, review it or
> merge it. A `.pbip` writes the model out as **TMDL**, which is plain text. That is
> the whole reason the semantic layer belongs in this repo rather than beside it.

## Step 2 — Create the parameter

New file, then `Home → Transform data` to open Power Query.

`Home → Manage Parameters → New Parameter`

| Field | Value |
|---|---|
| Name | `GoldFolder` |
| Type | Text |
| Current Value | `C:\Users\Avi\OneDrive\Desktop\retail-analytics-platform\data\gold` |

Every query reads from this, so moving the repo or handing it to someone else is a
one-value change rather than five query edits.

## Step 3 — Create the five queries

For each table below: `Home → New Source → Blank Query`, then
`Home → Advanced Editor`, replace the contents with the snippet, and rename the
query to match the table name exactly.

**`fct_sales`**

```m
let
    Source = Parquet.Document(
        File.Contents(GoldFolder & "\fct_sales.parquet")
    )
in
    Source
```

**`dim_customer`**

```m
let
    Source = Parquet.Document(
        File.Contents(GoldFolder & "\dim_customer.parquet")
    )
in
    Source
```

**`dim_product`**

```m
let
    Source = Parquet.Document(
        File.Contents(GoldFolder & "\dim_product.parquet")
    )
in
    Source
```

**`dim_country`**

```m
let
    Source = Parquet.Document(
        File.Contents(GoldFolder & "\dim_country.parquet")
    )
in
    Source
```

**`dim_date`**

```m
let
    Source = Parquet.Document(
        File.Contents(GoldFolder & "\dim_date.parquet")
    )
in
    Source
```

Names matter — the TMDL authored afterwards references them exactly as written.

## Step 4 — Load

`Close & Apply`.

`fct_sales` is ~1.03M rows and takes a minute or two. The four dimensions are
instant. Nothing needs transforming: shaping was dbt's job, and doing any of it
again here would split the logic across two tools.

## Step 5 — Save as a project

`File → Save as` → change the file type to **Power BI project file (*.pbip)**.

Save into the **repository root** as:

```
RetailAnalytics.pbip
```

That produces `RetailAnalytics.SemanticModel/` and `RetailAnalytics.Report/`
alongside it, both plain text.

## Step 6 — Confirm it worked

You should see, in the repo root:

```
RetailAnalytics.pbip
RetailAnalytics.SemanticModel/definition/tables/fct_sales.tmdl
RetailAnalytics.SemanticModel/definition/tables/dim_customer.tmdl
...
```

If `definition/tables/*.tmdl` files exist, step 1 worked. If you instead see a
single `.pbix`, the PBIP setting did not take — revisit step 1.

---

## What happens next

Once the project exists, the rest is authored as text and committed:

| Work | Where |
|---|---|
| Relationships (4, single-direction, one-to-many) | `definition/relationships.tmdl` |
| Measures — revenue, AOV, returns rate, retention | `definition/tables/_measures.tmdl` |
| Calculation group for time intelligence | `definition/tables/Time Intelligence.tmdl` |
| RLS role by country | `definition/roles/*.tmdl` |
| Column formatting, descriptions, hidden keys | per-table TMDL |
| Date table marked as such | `dim_date.tmdl` |

Reopen Power BI Desktop afterwards to refresh and build the report pages.

## Notes

- **Do not build relationships in the UI first.** They are authored in TMDL in one
  reviewable commit; doing both creates a merge conflict with yourself.
- `.gitignore` already excludes the data, so committing the project will not drag
  the 32 MB of parquet into git.
- Import mode is deliberate. DirectQuery over local parquet has no advantage here,
  and import keeps the model fast for a portfolio piece someone will click through.
