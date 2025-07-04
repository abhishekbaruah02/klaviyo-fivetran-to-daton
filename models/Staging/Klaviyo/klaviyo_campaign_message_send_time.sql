{% if  var('klaviyo_campaign_message_send_time') %}
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
table_pattern=var('klaviyo_campaign_message_send_time_table_pattern'),
database=var('raw_database')) %}

{% for i in relations %}
        select
        {{extract_nested_value("options_static","datetime","timestamp")}} as datetime,
        {{extract_nested_value("data","id","string")}} as campaign_message_id,
        {{extract_nested_value("options_static","is_local","boolean")}} as is_local,
        a.{{daton_user_id()}} as _daton_user_id,
        a.{{daton_batch_runtime()}} as _daton_batch_runtime,
        a.{{daton_batch_id()}} as _daton_batch_id,
        current_timestamp() as _last_updated,
        '{{env_var("DBT_CLOUD_RUN_ID", "manual")}}' as _run_id
        from {{i}} a
        {{unnesting("attributes")}}
        {{multi_unnesting('attributes','send_strategy')}}
        {{multi_unnesting('send_strategy','options_static')}}
        {{unnesting("relationships")}}
        {{multi_unnesting('relationships','campaignmessages')}}
        {{multi_unnesting('campaignmessages','data')}}

    {% if is_incremental() %}
        {# /* -- this filter will only be applied on an incremental run */ #}
        where {{max_loaded_batchruntime}}
    {% endif %}
    {% if not loop.last %} union all {% endif %}
{% endfor %}
qualify row_number() over (partition by {{extract_nested_value("data","id","string")}} order by _daton_batch_runtime desc) = 1