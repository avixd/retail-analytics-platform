-- Staging: rename, type and trim. No business rules and no rows dropped.
--
-- The only interpretive step here is classifying each line, and even that is
-- recorded rather than acted on: nothing is filtered until silver, so the counts
-- in this model still tie back to bronze exactly.

with source as (

    select * from {{ source('bronze', 'online_retail') }}

),

renamed as (

    select
        cast("Invoice"        as varchar)   as invoice_no,
        cast("StockCode"      as varchar)   as stock_code,
        nullif(trim(cast("Description" as varchar)), '') as description,
        cast("Quantity"       as integer)   as quantity,
        cast("InvoiceDate"    as timestamp) as invoice_ts,
        cast("Price"          as decimal(18, 4)) as unit_price,
        cast("Customer ID"    as bigint)    as customer_id,
        nullif(trim(cast("Country" as varchar)), '') as country,
        cast(source_sheet     as varchar)   as source_sheet,
        cast(_loaded_at       as timestamp) as loaded_at,
        cast(_source_sha256   as varchar)   as source_sha256

    from source

)

select
    *,

    -- A leading C marks a cancellation invoice. Note this does not account for
    -- every negative quantity: the profile found ~3.4k negative lines that are
    -- not on C invoices, which are treated as adjustments below.
    invoice_no like 'C%' as is_cancellation,

    case
        when invoice_no like 'C%' then 'cancellation'
        when quantity < 0         then 'adjustment'
        else 'sale'
    end as line_type,

    -- Genuine products carry a 5-digit code, optionally with a letter suffix.
    -- Everything else is postage, samples, bank charges, gift vouchers and so on,
    -- and must be excluded from product-level analysis without being deleted.
    not regexp_matches(coalesce(stock_code, ''), '^[0-9]{5}') as is_non_product,

    quantity * unit_price as line_amount

from renamed
