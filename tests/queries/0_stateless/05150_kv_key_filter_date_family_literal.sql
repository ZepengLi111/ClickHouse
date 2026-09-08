-- Tags: no-ordinary-database, no-fasttest, use-rocksdb
-- no-fasttest: rocksdb is not enabled in fasttest.

-- A key lookup narrows the candidates, so a literal of another type from the date family has to be
-- converted with its own type: reinterpreting its raw value in the key's unit space (days against
-- seconds) probes a key that does not exist, and the query silently returns no rows.

DROP TABLE IF EXISTS t_kv_date_literal;

CREATE TABLE t_kv_date_literal (key Date, value String) ENGINE = EmbeddedRocksDB PRIMARY KEY key;
INSERT INTO t_kv_date_literal VALUES ('2024-01-02', 'a');

SELECT count() FROM t_kv_date_literal WHERE key = toDate('2024-01-02');
SELECT count() FROM t_kv_date_literal WHERE key = toDateTime('2024-01-02 00:00:00', 'UTC');
SELECT count() FROM t_kv_date_literal WHERE key = toDateTime64('2024-01-02 00:00:00', 3, 'UTC');
SELECT count() FROM t_kv_date_literal WHERE key IN (toDateTime('2024-01-02 00:00:00', 'UTC'));
SELECT count() FROM t_kv_date_literal WHERE key = toDateTime('2024-01-03 00:00:00', 'UTC');

DROP TABLE t_kv_date_literal;

CREATE TABLE t_kv_date_literal (key DateTime('UTC'), value String) ENGINE = EmbeddedRocksDB PRIMARY KEY key;
INSERT INTO t_kv_date_literal VALUES ('2024-01-02 00:00:00', 'a');

SELECT count() FROM t_kv_date_literal WHERE key = toDateTime('2024-01-02 00:00:00', 'UTC');
SELECT count() FROM t_kv_date_literal WHERE key = toDate('2024-01-02');
SELECT count() FROM t_kv_date_literal WHERE key = toDateTime64('2024-01-02 00:00:00', 3, 'UTC');
SELECT count() FROM t_kv_date_literal WHERE key = toDate('2024-01-03');

DROP TABLE t_kv_date_literal;

CREATE TABLE t_kv_date_literal (key DateTime64(3, 'UTC'), value String) ENGINE = EmbeddedRocksDB PRIMARY KEY key;
INSERT INTO t_kv_date_literal VALUES ('2024-01-02 00:00:00.000', 'a');

SELECT count() FROM t_kv_date_literal WHERE key = toDateTime64('2024-01-02 00:00:00', 3, 'UTC');
SELECT count() FROM t_kv_date_literal WHERE key = toDate('2024-01-02');
SELECT count() FROM t_kv_date_literal WHERE key = toDateTime('2024-01-02 00:00:00', 'UTC');

DROP TABLE t_kv_date_literal;
