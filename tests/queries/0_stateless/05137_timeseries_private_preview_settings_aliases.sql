SELECT name, tier, alias_for
FROM system.settings
WHERE name IN
(
    'enable_time_series_table',
    'allow_experimental_time_series_table',
    'enable_time_series_aggregate_functions',
    'allow_experimental_time_series_aggregate_functions',
    'allow_experimental_ts_to_grid_aggregate_function',
    'time_series_prefer_recent_samples_table',
    'promql_database',
    'promql_table',
    'promql_evaluation_time'
)
ORDER BY name;

-- Both previous names of `enable_time_series_aggregate_functions` address the same value.
SET enable_time_series_table = 0, enable_time_series_aggregate_functions = 0;
SET allow_experimental_time_series_aggregate_functions = 1;
SELECT getSetting('enable_time_series_aggregate_functions'),
       getSetting('allow_experimental_time_series_aggregate_functions'),
       getSetting('allow_experimental_ts_to_grid_aggregate_function');
SELECT timeSeriesGroupArray(toDateTime64(0, 3, 'UTC'), 1::Float64);

SET allow_experimental_ts_to_grid_aggregate_function = 0;
SELECT getSetting('enable_time_series_aggregate_functions'),
       getSetting('allow_experimental_time_series_aggregate_functions'),
       getSetting('allow_experimental_ts_to_grid_aggregate_function');

SET allow_experimental_ts_to_grid_aggregate_function = 1;
SELECT timeSeriesGroupArray(toDateTime64(0, 3, 'UTC'), 1::Float64);

SET enable_time_series_aggregate_functions = 0;
SELECT name, value FROM system.settings
WHERE name IN ('enable_time_series_aggregate_functions',
               'allow_experimental_time_series_aggregate_functions',
               'allow_experimental_ts_to_grid_aggregate_function')
ORDER BY name;

-- The table setting also keeps its previous name as an alias.
SET allow_experimental_time_series_table = 1;
SELECT getSetting('enable_time_series_table'), getSetting('allow_experimental_time_series_table');
SET enable_time_series_table = 0;
SELECT getSetting('enable_time_series_table'), getSetting('allow_experimental_time_series_table');
