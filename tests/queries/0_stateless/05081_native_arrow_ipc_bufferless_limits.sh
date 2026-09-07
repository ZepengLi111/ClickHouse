#!/usr/bin/env bash
# Tags: no-fasttest
# This test requires PyArrow to write bufferless record batches.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh
set -e

TMP_DIR="${CLICKHOUSE_TMP}/${CLICKHOUSE_TEST_UNIQUE_NAME}"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TMP_DIR" <<'PY'
import os
import shlex
import subprocess
import sys
import pyarrow as pa
import pyarrow.ipc as ipc

out = sys.argv[1]
local = shlex.split(os.environ["CLICKHOUSE_LOCAL"]) + [
    "--path", f"{out}/local", "--max_threads=1", "--max_block_size=3",
]
rows = 257
batch = pa.record_batch([pa.nulls(rows)], names=["n"])

# Bufferless data remains readable incrementally. Metadata counts, early limits, and the query's result-row
# limit apply without materializing the batch's entire logical row count.
for fmt, writer_type in (("Arrow", ipc.new_file), ("ArrowStream", ipc.new_stream)):
    path = f"{out}/nulls.{fmt}"
    with writer_type(path, batch.schema) as writer:
        writer.write_batch(batch)
    source = f"file('{path}', '{fmt}', 'n Nullable(UInt8)')"
    count = subprocess.run(local + ["--query", f"SELECT count() FROM {source}"], text=True, capture_output=True)
    assert count.returncode == 0, count.stderr
    assert count.stdout == f"{rows}\n", count.stdout
    limited = subprocess.run(local + ["--query", f"SELECT n FROM {source} LIMIT 7"], text=True, capture_output=True)
    assert limited.returncode == 0, limited.stderr
    assert limited.stdout == "\\N\n" * 7, limited.stdout
    bounded = subprocess.run(local + [
        "--max_result_rows=20", "--result_overflow_mode=throw", "--query", f"SELECT n FROM {source}",
    ], text=True, capture_output=True)
    assert bounded.returncode != 0 and "TOO_MANY_ROWS" in bounded.stderr, (bounded.returncode, bounded.stdout, bounded.stderr)
    print(f"OK {fmt}: count, LIMIT, max_result_rows")
PY
