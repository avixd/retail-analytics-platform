-- Revenue must survive the trip from silver to gold.
--
-- Row-count tests catch rows going missing; they do not catch a join fanning out
-- and inflating money, which is the failure that actually reaches a board pack.
-- This compares the totals directly and allows a penny of rounding.

with silver as (

    select
        count(*)          as row_count,
        sum(line_amount)  as net_amount
    from {{ ref('silver_order_lines') }}

),

gold as (

    select
        count(*)          as row_count,
        sum(line_amount)  as net_amount
    from {{ ref('fct_sales') }}

)

select
    silver.row_count   as silver_rows,
    gold.row_count     as gold_rows,
    silver.net_amount  as silver_amount,
    gold.net_amount    as gold_amount,
    abs(silver.net_amount - gold.net_amount) as amount_delta
from silver, gold
where silver.row_count <> gold.row_count
   or abs(silver.net_amount - gold.net_amount) > 0.01
