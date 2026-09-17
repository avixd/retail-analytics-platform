-- Quarantine, not a bin. Every row silver_order_lines drops lands here with a
-- reason, so the pipeline can prove what it removed and why.
--
-- The reconciliation test in _silver.yml asserts:
--     silver_order_lines + silver_rejected_lines = stg_online_retail
-- which is what makes "we cleaned the data" an auditable claim rather than an
-- assertion.

with staged as (

    select * from {{ ref('stg_online_retail') }}

),

ranked as (

    select
        *,
        row_number() over (
            partition by invoice_no, stock_code, invoice_ts, quantity, unit_price, customer_id
            order by source_sheet
        ) as dup_rank

    from staged

)

select
    invoice_no,
    stock_code,
    description,
    quantity,
    unit_price,
    line_amount,
    invoice_ts,
    customer_id,
    country,
    line_type,
    source_sheet,

    -- Ordered deliberately: a row can be both a duplicate and a non-product, and
    -- the duplicate reason is the one that explains the row count.
    case
        when dup_rank > 1     then 'exact_duplicate'
        when is_non_product   then 'non_product_stock_code'
    end as reject_reason

from ranked
where dup_rank > 1
   or is_non_product
