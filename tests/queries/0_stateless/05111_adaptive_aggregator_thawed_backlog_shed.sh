#!/usr/bin/env bash

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

# Records staged before the thaw stay published for the merge-time drain, so a producer the thaw put
# back on the baseline path keeps holding them for the rest of the query and cannot free them by
# flushing its own table. The baseline spill decision is read from query-wide memory, so that
# residency keeps the threshold crossed on every following block, and each block leaves a temporary
# file holding a single block's keys. The frozen path shed the backlog under the same trigger
# already; the thawed one has to as well.
#
# The stream is the one from 05054: repeat-dominated wide keys freeze the tables, and the staged
# stream then proves repeat-dominated and thaws them. Two producers keep the whole backlog resident.
# The thaw cannot fire before 524288 staged records, which at these key widths is about 42 MB of
# them, so the threshold has to sit above that or the sweeps shed the backlog before the thaw and
# there is nothing left to stay resident.
#
# What carries the query back over the threshold after the thaw is the growth of the two baseline
# tables the thaw hands the producers, on top of the resident backlog, so the key space is wide
# enough that this growth is several times the margin the backlog leaves rather than comparable to
# it. Measured on this tree, the shedding then still fires over the whole 30-80 MB band of
# thresholds, instead of only the 42-66 MB the 50000-key stream held it in, where a producer that
# ran a little ahead of its twin could let the frozen sweeps shed the backlog before the thaw and
# leave nothing resident. That narrow band is what made this test flaky in CI.
#
# What the assertions bound is the part count, not the peak: measured with this binary the resident
# backlog costs 365-390 parts against 5-7 with it shed, while the peak differs by half a threshold.
# The memory limit is left as generous as the rest of the family's, so that a sanitizer arm, which
# pays several times over per part written and read back, cannot fail on the peak alone; the shed
# arm peaks under 100 MB here.
#
# The query runs in its own clickhouse-local process, so the counters in `system.events` belong to
# it alone.
$CLICKHOUSE_LOCAL --query "
SET max_threads = 2;
SET max_block_size = 8192;
SET enable_adaptive_aggregator = 1;
SET adaptive_aggregator_freeze_threshold = 1000;
SET adaptive_aggregator_freeze_threshold_bytes = 0;
SET group_by_two_level_threshold = 1000;
SET group_by_two_level_threshold_bytes = 1000000;
SET max_bytes_before_external_group_by = 56000000;
SET max_bytes_ratio_before_external_group_by = 0;
SET max_memory_usage = 300000000;
-- The hash-table statistics remember the thaw verdict and a marked query skips the adaptive
-- engagement, so without this only the first run of the shape would reach it.
SET collect_hash_table_stats_during_aggregation = 0;

SELECT count() FROM
(
    SELECT concat(toString(number % 100000), repeat('x', 60)) AS k
    FROM numbers_mt(4000000)
    GROUP BY k
);

-- This event is incremented only from the new hook, on the thawed baseline spill path in
-- Aggregator::executeOnBlock, so it is what proves that path was taken. The two liveness
-- assertions below it are satisfiable by the pre-existing finish-time drain as well, and the part
-- bound is the oracle; this one pins the hook itself.
SELECT 'shed the backlog on the thawed spill path',
       sumIf(value, event = 'AdaptiveAggregationSpillBacklogSheds') > 0
FROM system.events;
-- Parts are written only once query memory crosses the external threshold, which is the condition
-- the shedding is guarded by, so this is what proves the baseline spill decision was reached.
SELECT 'went external', sumIf(value, event = 'ExternalAggregationWritePart') > 0 FROM system.events;
-- One part per block is the defect: a producer that finds the backlog resident on every block
-- writes its own few keys out on every block. 4000000 rows in blocks of 8192 is 488 blocks, and an
-- eighth of that leaves the handful of parts a shed backlog costs a wide margin.
SELECT 'parts stay far below the block count',
       sumIf(value, event = 'ExternalAggregationWritePart') * 8 < intDiv(4000000, 8192)
FROM system.events;
-- Without these the test could pass by never engaging the adaptive aggregator, or by never leaving
-- the frozen path, whose shedding is not what this covers.
SELECT 'thawed onto the baseline path', sumIf(value, event = 'AdaptiveAggregationThaws') > 0 FROM system.events;
SELECT 'swept under pressure', sumIf(value, event = 'AdaptiveAggregationPressureSweeps') > 0 FROM system.events;
"
