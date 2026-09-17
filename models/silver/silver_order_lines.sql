-- Silver: the conformed, trustworthy grain. One row per genuine order line.
--
-- Two decisions are made here, both quarantining rather than deleting. Anything
-- removed lands in silver_rejected_lines with a reason, and a dbt test asserts
-- that silver + rejected reconciles back to staging exactly.
--
-- DECISION 1 - exact duplicates are collapsed.
--   34,335 rows repeat an identical (invoice, stock, timestamp, quantity, price,
--   customer). 32,909 of those groups share a timestamp to the *second*, which a
--   till does not produce for separate scans, so they read as an extract artefact.
--   Collapsing them moves gross sales by GBP 496,886 (2.39%) - material enough
--   that it is stated in the README rather than buried here.
--
-- DECISION 2 - non-products are excluded from the line grain.
--   Postage, bank charges, samples and gift vouchers are real money but they are
--   not products, and leaving them in silently corrupts any per-product measure.

with staged as (

    select * from {{ ref('stg_online_retail') }}

),

ranked as (

    select
        *,
        row_number() over (
            partition by invoice_no, stock_code, invoice_ts, quantity, unit_price, customer_id
            order by source_sheet
        ) as dup_rank,
        count(*) over (
            partition by invoice_no, stock_code, invoice_ts, quantity, unit_price, customer_id
        ) as dup_group_size

    from staged

)

select
    {{ dbt_utils.generate_surrogate_key(['invoice_no', 'stock_code', 'invoice_ts', 'quantity', 'unit_price']) }} as order_line_key,

    invoice_no,
    stock_code,
    description,
    quantity,
    unit_price,
    line_amount,
    invoice_ts,
    cast(invoice_ts as date) as invoice_date,

    -- ~23% of lines have no customer. They are kept - they are real revenue - and
    -- routed to a single "Unknown" member so customer-level measures stay honest
    -- instead of quietly excluding a fifth of the business.
    customer_id,
    coalesce(cast(customer_id as varchar), 'UNKNOWN') as customer_key,
    customer_id is null as is_guest,

    country,
    line_type,
    is_cancellation,
    dup_group_size > 1 as was_duplicated,
    source_sheet,
    loaded_at

from ranked
where dup_rank = 1
  and not is_non_product
