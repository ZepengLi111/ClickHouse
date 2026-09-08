#!/usr/bin/env bash
# Tags: no-fasttest

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

STR_PATH="${CLICKHOUSE_USER_FILES}/lakehouses/${CLICKHOUSE_DATABASE}_str"
NUM_PATH="${CLICKHOUSE_USER_FILES}/lakehouses/${CLICKHOUSE_DATABASE}_num"
PLAIN_PATH="${CLICKHOUSE_USER_FILES}/lakehouses/${CLICKHOUSE_DATABASE}_plain"
DEL_PATH="${CLICKHOUSE_USER_FILES}/lakehouses/${CLICKHOUSE_DATABASE}_del"

rm -rf "${STR_PATH}" "${NUM_PATH}" "${PLAIN_PATH}" "${DEL_PATH}"

# Manifests are named after a UUID, manifest lists are named 'snap-...', so this glob picks up the
# manifests only; a '*' glob would mix the two incompatible Avro schemas in one file() call.
MANIFEST_GLOB='????????-????-????-????-????????????.avro'

${CLICKHOUSE_CLIENT} --query "
    SET allow_experimental_insert_into_iceberg = 1;
    DROP TABLE IF EXISTS str;
    CREATE TABLE str (region String, id Int32)
    ENGINE = IcebergLocal('${STR_PATH}', 'Parquet') PARTITION BY (region) ORDER BY (id);
    INSERT INTO str SELECT if(number < 2, 'eu', 'us'), number FROM numbers(4);
"

# Every manifest holds exactly one partition, so its manifest-list field summary must pin both bounds
# to that partition. The bounds are joined back to the partition value stored inside the manifest they
# describe, so a summary attached to the wrong entry moves the output.
echo '--- string partition: bounds pin the manifest to its own partition ---'
${CLICKHOUSE_CLIENT} --query "
    WITH entries AS (
        SELECT
            replaceRegexpOne(manifest_path, '^.*/', '')            AS base,
            length(partitions)                                     AS summaries,
            tupleElement(partitions[1], 'contains_null')           AS contains_null,
            tupleElement(partitions[1], 'contains_nan')            AS contains_nan,
            tupleElement(partitions[1], 'lower_bound')             AS lower_bound,
            tupleElement(partitions[1], 'upper_bound')             AS upper_bound
        FROM file('${STR_PATH}/metadata/snap-*.avro', Avro)
    ),
    manifests AS (
        SELECT
            replaceRegexpOne(_path, '^.*/', '')                    AS base,
            any(tupleElement(data_file, 'partition').1)            AS own_partition
        FROM file('${STR_PATH}/metadata/${MANIFEST_GLOB}', Avro)
        GROUP BY base
    )
    SELECT
        'partition=' || m.own_partition
          || ' summaries=' || toString(e.summaries)
          || ' contains_null=' || toString(e.contains_null)
          || ' contains_nan=' || ifNull(toString(e.contains_nan), 'NULL')
          || ' bounds=' || toString((e.lower_bound, e.upper_bound))
          || ' bounds_are_own_partition=' || if(e.lower_bound = m.own_partition AND e.upper_bound = m.own_partition, 'yes', 'no') AS entry
    FROM entries AS e INNER JOIN manifests AS m ON e.base = m.base
    ORDER BY m.own_partition
    FORMAT TSV;
"

# Numeric bounds are raw little-endian bytes, like the data-file bounds in the manifests themselves.
${CLICKHOUSE_CLIENT} --query "
    SET allow_experimental_insert_into_iceberg = 1;
    DROP TABLE IF EXISTS num;
    CREATE TABLE num (part Int32, id Int32)
    ENGINE = IcebergLocal('${NUM_PATH}', 'Parquet') PARTITION BY (part) ORDER BY (id);
    INSERT INTO num SELECT number % 2 + 10, number FROM numbers(4);
"

echo '--- Int32 partition: bounds decode to the partition value ---'
${CLICKHOUSE_CLIENT} --query "
    WITH entries AS (
        SELECT
            replaceRegexpOne(manifest_path, '^.*/', '')                            AS base,
            reinterpretAsInt32(tupleElement(partitions[1], 'lower_bound'))         AS lower_bound,
            reinterpretAsInt32(tupleElement(partitions[1], 'upper_bound'))         AS upper_bound
        FROM file('${NUM_PATH}/metadata/snap-*.avro', Avro)
    ),
    manifests AS (
        SELECT
            replaceRegexpOne(_path, '^.*/', '')                                    AS base,
            any(tupleElement(data_file, 'partition').1)                            AS own_partition
        FROM file('${NUM_PATH}/metadata/${MANIFEST_GLOB}', Avro)
        GROUP BY base
    )
    SELECT
        'partition=' || toString(m.own_partition)
          || ' bounds=' || toString((e.lower_bound, e.upper_bound))
          || ' bounds_are_own_partition=' || if(e.lower_bound = m.own_partition AND e.upper_bound = m.own_partition, 'yes', 'no') AS entry
    FROM entries AS e INNER JOIN manifests AS m ON e.base = m.base
    ORDER BY m.own_partition
    FORMAT TSV;
"

# An unpartitioned table has no partition fields, so the summary list stays empty.
${CLICKHOUSE_CLIENT} --query "
    SET allow_experimental_insert_into_iceberg = 1;
    DROP TABLE IF EXISTS plain;
    CREATE TABLE plain (id Int32) ENGINE = IcebergLocal('${PLAIN_PATH}', 'Parquet') ORDER BY (id);
    INSERT INTO plain SELECT number FROM numbers(4);
"

echo '--- unpartitioned: no field summaries ---'
${CLICKHOUSE_CLIENT} --query "
    SELECT count() AS entries, sum(length(partitions)) AS summaries
    FROM file('${PLAIN_PATH}/metadata/snap-*.avro', Avro)
    FORMAT TSV;
"

# A later snapshot copies the manifests of its parent into the new manifest list, and DELETE adds a
# position-delete manifest of its own: both kinds of entry must carry bounds.
${CLICKHOUSE_CLIENT} --query "
    SET allow_experimental_insert_into_iceberg = 1;
    DROP TABLE IF EXISTS del;
    CREATE TABLE del (region String, id Int32)
    ENGINE = IcebergLocal('${DEL_PATH}', 'Parquet') PARTITION BY (region) ORDER BY (id);
    INSERT INTO del SELECT if(number < 2, 'eu', 'us'), number FROM numbers(4);
    DELETE FROM del WHERE id = 0;
"

echo '--- after DELETE: carried-forward and position-delete entries keep bounds ---'
# Snapshot file names carry the snapshot id, not an increasing counter, so the manifest list of the
# DELETE is picked by modification time.
LATEST_SNAPSHOT=$(find "${DEL_PATH}/metadata" -maxdepth 1 -name 'snap-*.avro' -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
${CLICKHOUSE_CLIENT} --query "
    SELECT
        'content=' || toString(content)
          || ' bounds=' || toString((tupleElement(partitions[1], 'lower_bound'), tupleElement(partitions[1], 'upper_bound'))) AS entry
    FROM file('${LATEST_SNAPSHOT}', Avro)
    ORDER BY content, tupleElement(partitions[1], 'lower_bound')
    FORMAT TSV;
"

echo '--- data reads back unchanged ---'
${CLICKHOUSE_CLIENT} --query "SELECT * FROM del ORDER BY id FORMAT TSV;"

rm -rf "${STR_PATH}" "${NUM_PATH}" "${PLAIN_PATH}" "${DEL_PATH}"
