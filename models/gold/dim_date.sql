-- Date dimension, generated to cover whole calendar years around the data.
--
-- Deliberately generated rather than derived from observed invoice dates: a date
-- dimension with gaps breaks time intelligence, and Power BI needs a contiguous
-- table to mark as the date table.
--
-- The fiscal columns assume an April start, which is the UK retail convention
-- this dataset sits in. Changing the offset is a one-line edit here rather than a
-- rewrite of every measure.

{% set fiscal_start_month = 4 %}

with bounds as (

    select
        date_trunc('year', min(invoice_date)) as min_date,
        date_trunc('year', max(invoice_date)) + interval 1 year - interval 1 day as max_date
    from {{ ref('silver_order_lines') }}

),

calendar as (

    select unnest(generate_series(
        (select min_date from bounds),
        (select max_date from bounds),
        interval 1 day
    ))::date as date_day

)

select
    cast(strftime(date_day, '%Y%m%d') as integer) as date_key,
    date_day,

    year(date_day)      as calendar_year,
    quarter(date_day)   as calendar_quarter,
    month(date_day)     as month_number,
    strftime(date_day, '%B') as month_name,
    strftime(date_day, '%b') as month_short,
    date_trunc('month', date_day) as month_start,
    -- Sorting a month name alphabetically is the classic Power BI trap; this is
    -- the column to sort it by.
    cast(strftime(date_day, '%Y%m') as integer) as year_month_key,

    week(date_day)       as iso_week,
    dayofweek(date_day)  as day_of_week,
    strftime(date_day, '%A') as day_name,
    dayofweek(date_day) in (0, 6) as is_weekend,

    case
        when month(date_day) >= {{ fiscal_start_month }} then year(date_day)
        else year(date_day) - 1
    end as fiscal_year,
    ((month(date_day) - {{ fiscal_start_month }} + 12) % 12) + 1 as fiscal_month_number

from calendar
