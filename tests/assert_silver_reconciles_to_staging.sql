-- The load-bearing test of the whole silver layer.
--
-- Cleaning is only trustworthy if nothing vanished unaccounted for. Kept rows
-- plus quarantined rows must equal what arrived. This returns rows (and so
-- fails) whenever those three numbers stop agreeing.

with counts as (

    select
        (select count(*) from {{ ref('stg_online_retail')    }}) as staging_rows,
        (select count(*) from {{ ref('silver_order_lines')   }}) as kept_rows,
        (select count(*) from {{ ref('silver_rejected_lines') }}) as rejected_rows

)

select
    staging_rows,
    kept_rows,
    rejected_rows,
    kept_rows + rejected_rows as accounted_for,
    staging_rows - (kept_rows + rejected_rows) as unaccounted
from counts
where staging_rows <> kept_rows + rejected_rows
