-- Sales fact at order-line grain, one row per line in silver.
--
-- Cancellations and adjustments stay in the fact rather than being split out, so
-- that net revenue is the default and gross has to be asked for explicitly. The
-- signed line_amount does that work: summing it gives net, and the split measures
-- below let a report separate the two without a second table to keep in step.
--
-- Country is carried on the fact, not taken from the customer, because 12
-- customers transact from more than one country and the order knows where it
-- actually shipped.

with lines as (

    select * from {{ ref('silver_order_lines') }}

)

select
    l.order_line_key,

    -- Foreign keys
    cast(strftime(l.invoice_date, '%Y%m%d') as integer) as date_key,
    {{ dbt_utils.generate_surrogate_key(['l.customer_key']) }} as customer_key_sk,
    {{ dbt_utils.generate_surrogate_key(['l.stock_code']) }}   as product_key,
    {{ dbt_utils.generate_surrogate_key(['l.country']) }}      as country_key,

    -- Degenerate dimension
    l.invoice_no,
    l.line_type,
    l.is_cancellation,
    l.is_guest,

    -- Measures
    l.quantity,
    l.unit_price,
    l.line_amount,
    case when l.line_type = 'sale'         then l.line_amount else 0 end as gross_sales_amount,
    case when l.line_type = 'cancellation' then l.line_amount else 0 end as cancellation_amount,
    case when l.line_type = 'sale'         then l.quantity    else 0 end as units_sold,

    l.invoice_ts,
    l.invoice_date

from lines l
