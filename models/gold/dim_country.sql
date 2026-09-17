-- Country dimension. Small, but a real table rather than a text column on the
-- fact, so the model stays a clean star and country attributes have somewhere to
-- live when they are needed.

with lines as (

    select * from {{ ref('silver_order_lines') }}

),

stats as (

    select
        country,
        count(distinct invoice_no)    as invoice_count,
        count(distinct customer_key)  as customer_count,
        sum(case when line_type = 'sale' then line_amount else 0 end) as gross_sales,
        min(invoice_date) as first_order_date,
        max(invoice_date) as last_order_date
    from lines
    group by country

)

select
    {{ dbt_utils.generate_surrogate_key(['country']) }} as country_key,
    country,
    -- The dataset is a UK retailer, so domestic vs export is the split that
    -- actually drives the commentary.
    country = 'United Kingdom' as is_domestic,
    country in ('Unspecified', 'European Community') as is_unallocated,
    invoice_count,
    customer_count,
    gross_sales,
    first_order_date,
    last_order_date
from stats
