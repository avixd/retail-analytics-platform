-- Customer dimension, including a single conformed member for guest checkouts.
--
-- Guests are 22.7% of lines. Excluding them would be tidier and would misstate
-- the business by nearly a quarter, so they collapse into one UNKNOWN member that
-- is explicitly flagged - visible in any report rather than quietly missing.
--
-- 12 customers transact from more than one country. Country is therefore an
-- attribute of the *order*, not reliably of the customer; the most recent one is
-- carried here for convenience and fct_sales keeps the per-order country as the
-- authoritative value.

with lines as (

    select * from {{ ref('silver_order_lines') }}

),

latest_country as (

    select customer_key, country
    from (
        select
            customer_key,
            country,
            row_number() over (partition by customer_key order by max(invoice_ts) desc) as rn
        from lines
        group by customer_key, country
    )
    where rn = 1

),

stats as (

    select
        customer_key,
        bool_and(is_guest) as is_guest,
        min(invoice_date) as first_order_date,
        max(invoice_date) as last_order_date,
        count(distinct invoice_no) as order_count,
        count(distinct country) as country_count,
        sum(case when line_type = 'sale' then line_amount else 0 end) as gross_sales,
        sum(case when line_type = 'cancellation' then line_amount else 0 end) as cancellations
    from lines
    group by customer_key

)

select
    {{ dbt_utils.generate_surrogate_key(['s.customer_key']) }} as customer_key_sk,
    s.customer_key,
    s.is_guest,
    c.country,
    s.country_count > 1 as has_multiple_countries,
    s.first_order_date,
    s.last_order_date,
    date_trunc('month', s.first_order_date) as cohort_month,
    s.order_count,
    s.gross_sales,
    s.cancellations,
    s.gross_sales + s.cancellations as net_sales
from stats s
left join latest_country c using (customer_key)
