{% if  var('klaviyo_campaign_list',True) %}
{{ config( enabled = True ) }}
{% else %}
{{ config( enabled = False ) }}
{% endif %}

{% if is_incremental() %}
    {% set max_loaded_batchruntime = '_daton_batch_runtime >= (select coalesce(max(_daton_batch_runtime),0) from ' ~ this ~ ')' %}
{% else %}
    {% set max_loaded_batchruntime = '1=1' %}
{% endif %}

{% set relations = dbt_utils.get_relations_by_pattern(
schema_pattern=var('raw_schema'),
table_pattern=var('klaviyo_campaign_list_table_pattern'),
database=var('raw_database')) %}

with raw_data as (
{% for i in relations %}
        select
        coalesce(a.id, 'NA') as campaign_id,
        {{extract_nested_value("audiences","included","string")}} as included,
        {{extract_nested_value("audiences","excluded","string")}} as excluded,
        a.{{daton_user_id()}} as _daton_user_id,
        a.{{daton_batch_runtime()}} as _daton_batch_runtime,
        a.{{daton_batch_id()}} as _daton_batch_id,
        current_timestamp() as _last_updated,
        '{{env_var("DBT_CLOUD_RUN_ID", "manual")}}' as _run_id
        from {{i}} a
        {{unnesting("attributes")}}
        {{multi_unnesting('attributes','audiences')}}

    {% if is_incremental() %}
        {# /* -- this filter will only be applied on an incremental run */ #}
        where {{max_loaded_batchruntime}}
    {% endif %}
    {% if not loop.last %} union all {% endif %}
{% endfor %}
qualify row_number() over (partition by id order by _daton_batch_runtime desc) = 1
),
main as (
SELECT
  campaign_id,
  TRIM(lists) AS list_id,
  'included' AS list_included_or_excluded
FROM raw_data,
UNNEST(SPLIT(included)) AS lists
WHERE included IS NOT NULL

UNION ALL

SELECT
  campaign_id,
  TRIM(lists) AS list_id,
  'excluded' AS list_included_or_excluded
FROM raw_data,
UNNEST(SPLIT(excluded)) AS lists
WHERE excluded IS NOT NULL
)
select * from main