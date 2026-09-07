-- The join-order conflict detectors reorder outer joins using null-rejection (paper Definition 1),
-- which is only sound when an unmatched outer-join row is padded with a real SQL NULL. Under the
-- default join_use_nulls = 0 the padding is a type default (0/''), so a "null-rejecting" predicate
-- like t2.id = t3.id still matches the padded 0, and reordering (t1 LEFT JOIN t2) LEFT JOIN t3 into
-- t1 LEFT JOIN (t2 LEFT JOIN t3) changes the result. Regression test for
-- https://github.com/ClickHouse/ClickHouse/issues/118520: the detector must return exactly the
-- unoptimized rows. The counts and the padded-key row below are the unoptimized (limit = 0) results;
-- with the detector on they must be unchanged.

DROP TABLE IF EXISTS t1;
DROP TABLE IF EXISTS t2;
DROP TABLE IF EXISTS t3;

CREATE TABLE t1 (id UInt64, value String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE t2 (id UInt64, value String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE t3 (id UInt64, value String) ENGINE = MergeTree ORDER BY id;
INSERT INTO t1 VALUES (0,'v1_0'),(1,'v1_1'),(2,'v1_2');
INSERT INTO t2 VALUES (0,'v2_0'),(1,'v2_1'),(3,'v2_3');
INSERT INTO t3 VALUES (0,'v3_0'),(1,'v3_1'),(4,'v3_4');

SET enable_analyzer = 1, single_join_prefer_left_table = 0;
-- Make t1 look expensive so the detector prefers to reorder t2/t3 to the front.
SET param__internal_join_table_stat_hints = '{"t1": {"cardinality": 100000, "distinct_keys": {"id": 2}}, "t2": {"cardinality": 3, "distinct_keys": {"id": 3}}, "t3": {"cardinality": 3, "distinct_keys": {"id": 3}}}';

SELECT 'LEFT+LEFT   cd_c', count() FROM t1 LEFT JOIN t2 ON t1.id = t2.id LEFT JOIN t3 ON t2.id = t3.id
    SETTINGS query_plan_optimize_join_order_algorithm = 'dpsub', query_plan_optimize_join_order_use_conflict_detector_c = 1;
SELECT 'LEFT+LEFT   cd_a', count() FROM t1 LEFT JOIN t2 ON t1.id = t2.id LEFT JOIN t3 ON t2.id = t3.id
    SETTINGS query_plan_optimize_join_order_algorithm = 'dpsub', query_plan_optimize_join_order_use_conflict_detector_a = 1;

-- The row that exposed the bug: t1.id = 2 has no t2 match, so t2.id is padded 0; the downstream
-- t2.id = t3.id then legitimately matches t3.id = 0 under join_use_nulls = 0. The reorder must keep
-- t3.value = 'v3_0' here, not drop it to ''.
SELECT 'padded-key row  ', t1.id, t2.id, t3.id, t3.value
FROM t1 LEFT JOIN t2 ON t1.id = t2.id LEFT JOIN t3 ON t2.id = t3.id
WHERE t1.id = 2
    SETTINGS query_plan_optimize_join_order_algorithm = 'dpsub', query_plan_optimize_join_order_use_conflict_detector_c = 1;

DROP TABLE t1;
DROP TABLE t2;
DROP TABLE t3;
