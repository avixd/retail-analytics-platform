-- Product dimension. Type 1: the current description wins, no history kept.
--
-- The source has no product master, so the dimension is derived from transactions
-- and two problems have to be resolved rather than ignored:
--
--   1,207 stock codes carry more than one description - typos, casing drift and
--   genuine renames all mixed together. The most frequently used description wins,
--   with the most recent used to break ties, because frequency tracks the settled
--   name while recency alone would let a single late typo rewrite the product.
--
--     335 stock codes have no description on any line. They are kept, because
--   their sales are real, and labelled so they are visibly unknown rather than
--   silently blank in a report.

with lines as (

    select * from {{ ref('silver_order_lines') }}

),

description_ranked as (

    select
        stock_code,
        description,
        row_number() over (
            partition by stock_code
            order by count(*) desc, max(invoice_ts) desc, description
        ) as rn
    from lines
    where description is not null
    group by stock_code, description

),

product_stats as (

    select
        stock_code,
        min(invoice_date) as first_sold_date,
        max(invoice_date) as last_sold_date,
        count(distinct invoice_no) as invoice_count,
        sum(case when line_type = 'sale' then quantity else 0 end) as units_sold,
        round(avg(unit_price), 4) as avg_unit_price,
        count(distinct description) as description_variants
    from lines
    group by stock_code

)

select
    {{ dbt_utils.generate_surrogate_key(['s.stock_code']) }} as product_key,
    s.stock_code,
    coalesce(d.description, '(no description)') as description,
    d.description is null as is_description_missing,
    s.description_variants,
    s.first_sold_date,
    s.last_sold_date,
    s.invoice_count,
    s.units_sold,
    s.avg_unit_price
from product_stats s
left join description_ranked d
    on d.stock_code = s.stock_code
   and d.rn = 1
