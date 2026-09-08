#!/usr/bin/env bash
# Tags: no-fasttest

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

# A loaded runner can need more than the default 10 s `connect_timeout` /
# `handshake_timeout_ms` to accept the connection and send Hello; the benchmark
# then aborts before its final report and prints no summary at all.
$CLICKHOUSE_BENCHMARK --connect_timeout 60 --handshake_timeout_ms 60000 --iterations=10 --reconnect=2 <<< 'SELECT 1' 2>&1 | grep -F 'Queries executed' | tail -n1
