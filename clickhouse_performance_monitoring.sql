-- ============================================================
-- ClickHouse Performance Monitoring Queries
-- 15 SQL queries for monitoring and analyzing ClickHouse
-- Author: shiviyer
-- ============================================================


-- ============================================================
-- Query 1: Currently Running Queries
-- Monitor all active queries with elapsed time and memory usage
-- ============================================================
SELECT
    query_id,
    user,
    elapsed
    formatReadableSize(memory_usage) AS memory_usage,
    formatReadableSize(read_bytes)   AS read_bytes,
    read_rows,
    query
FROM system.processes
ORDER BY elapsed DESC;


-- ============================================================
-- Query 2: Top Slow Queries (Last 24 Hours)
-- Identify the slowest queries from the query log
-- ============================================================
SELECT
    query_id,
    user,
    query_duration_ms / 1000.0                  AS duration_sec,
    formatReadableSize(memory_usage)             AS memory_usage,
    formatReadableSize(read_bytes)               AS read_bytes,
    read_rows,
    result_rows,
    type,
    event_time,
    LEFT(query, 200)                             AS query_snippet
FROM system.query_log
WHERE
    type = 'QueryFinish'
    AND event_time >= now() - INTERVAL 1 DAY
ORDER BY query_duration_ms DESC
LIMIT 20;


-- ============================================================
-- Query 3: Query Errors in the Last Hour
-- Detect failed queries and their error messages
-- ============================================================
SELECT
    event_time,
    user,
    query_id,
    exception_code,
    exception,
    LEFT(query, 200) AS query_snippet
FROM system.query_log
WHERE
    type = 'ExceptionWhileProcessing'
    AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 50;


-- ============================================================
-- Query 4: Memory Usage Per Database and Table
-- Understand which tables consume the most memory (primary index)
-- ============================================================
SELECT
    database,
    table,
    formatReadableSize(SUM(primary_key_bytes_in_memory)) AS primary_key_mem,
    formatReadableSize(SUM(bytes_on_disk))               AS disk_size,
    SUM(rows)                                            AS total_rows,
    COUNT()                                              AS part_count
FROM system.parts
WHERE active = 1
GROUP BY database, table
ORDER BY SUM(bytes_on_disk) DESC
LIMIT 30;


-- ============================================================
-- Query 5: Disk Usage Overview
-- Monitor disk space consumption across all disks
-- ============================================================
SELECT
    name                                    AS disk_name,
    path,
    formatReadableSize(free_space)          AS free_space,
    formatReadableSize(total_space)         AS total_space,
    formatReadableSize(total_space - free_space) AS used_space,
    ROUND((1 - free_space / nullIf(total_space, 0)) * 100, 2) AS used_pct
FROM system.disks
ORDER BY total_space DESC;


-- ============================================================
-- Query 6: Active Merges
-- Check ongoing merge operations and their progress
-- ============================================================
SELECT
    database,
    table,
    elapsed,
    ROUND(progress * 100, 2)                  AS progress_pct,
    formatReadableSize(total_size_bytes_compressed) AS total_size,
    num_parts,
    result_part_name,
    merge_type
FROM system.merges
ORDER BY elapsed DESC;


-- ============================================================
-- Query 7: Replication Status
-- Monitor replication lag and health for replicated tables
-- ============================================================
SELECT
    database,
    table,
    engine,
    is_leader,
    can_become_leader,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_max_index - log_pointer        AS replication_lag,
    total_replicas,
    active_replicas,
    last_queue_update
FROM system.replicas
ORDER BY replication_lag DESC;


-- ============================================================
-- Query 8: Query Throughput Per User (Last Hour)
-- Understand query load distribution by user
-- ============================================================
SELECT
    user,
    COUNT(*)                                     AS total_queries,
    COUNTIf(type = 'QueryFinish')                AS successful,
    COUNTIf(type = 'ExceptionWhileProcessing')   AS failed,
    ROUND(AVG(query_duration_ms), 2)             AS avg_duration_ms,
    formatReadableSize(SUM(memory_usage))        AS total_memory,
    formatReadableSize(SUM(read_bytes))          AS total_read_bytes
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 HOUR
GROUP BY user
ORDER BY total_queries DESC;


-- ============================================================
-- Query 9: Large Parts & Partition Overview
-- Find tables with oversized or too many parts
-- ============================================================
SELECT
    database,
    table,
    partition_id,
    COUNT()                                AS part_count,
    formatReadableSize(SUM(bytes_on_disk)) AS partition_size,
    SUM(rows)                              AS total_rows,
    MIN(min_date)                          AS min_date,
    MAX(max_date)                          AS max_date
FROM system.parts
WHERE active = 1
GROUP BY database, table, partition_id
HAVING part_count > 10
ORDER BY part_count DESC
LIMIT 30;


-- ============================================================
-- Query 10: System Metric Snapshots
-- Retrieve current key performance metrics from system.metrics
-- ============================================================
SELECT
    metric,
    value,
    description
FROM system.metrics
WHERE metric IN (
      'Query',
      'Merge',
      'BackgroundPoolTask',
      'BackgroundFetchesPoolTask',
      'MemoryTracking',
      'OpenFileForRead',
      'OpenFileForWrite',
      'ReplicatedChecks',
      'NetworkReceive',
      'NetworkSend',
      'DiskSpaceReservedForMerge',
      'DistributedFilesToInsert'
  )
ORDER BY metric;


-- ============================================================
-- Query 11: Asynchronous Metric History (Last 5 Minutes)
-- Track system-level metrics over time
-- ============================================================
SELECT
    event_time,
    metric,
    value
FROM system.asynchronous_metric_log
WHERE
    event_time >= now() - INTERVAL 5 MINUTE
    AND metric IN (
          'jemalloc.allocated',
          'jemalloc.resident',
          'CGroupMemoryUsed',
          'OSUserTimeCPU',
          'OSIOWaitMicroseconds',
          'OSReadBytes',
          'OSWriteBytes'
      )
ORDER BY event_time DESC, metric;


-- ============================================================
-- Query 12: Mutations Status
-- Track ALTER TABLE mutations and their progress
-- ============================================================
SELECT
    database,
    table,
    mutation_id,
    command,
    create_time,
    parts_to_do_names,
    parts_to_do,
    is_done,
    latest_failed_part,
    latest_failure_time,
    latest_fail_reason
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time DESC;


-- ============================================================
-- Query 13: Distributed Table Queue
-- Monitor pending inserts in distributed tables
-- ============================================================
SELECT
    database,
    table,
    data_path,
    formatReadableSize(bytes_on_disk) AS queue_size_on_disk,
    files_count,
    broken_files_count,
    last_exception
FROM system.distribution_queue
ORDER BY bytes_on_disk DESC;


-- ============================================================
-- Query 14: Cache Hit Rates
-- Monitor mark cache and uncompressed cache effectiveness
-- ============================================================
SELECT
    metric,
    value
FROM system.metrics
WHERE metric IN (
      'MarkCacheFiles',
      'MarkCacheBytes',
      'UncompressedCacheBytes',
      'UncompressedCacheCells',
      'MMappedFiles',
      'MMappedFileBytes'
  )
UNION ALL
SELECT
    event AS metric,
    value
FROM system.events
WHERE event IN (
      'MarkCacheHits',
      'MarkCacheMisses',
      'UncompressedCacheHits',
      'UncompressedCacheMisses',
      'QueryCacheHits',
      'QueryCacheMisses'
  )
ORDER BY metric;


-- ============================================================
-- Query 15: Table Engine and Compression Stats
-- Analyze compression ratios and storage efficiency per table
-- ============================================================
SELECT
    database,
    table,
    engine,
    formatReadableSize(SUM(data_compressed_bytes))   AS compressed_size,
    formatReadableSize(SUM(data_uncompressed_bytes)) AS uncompressed_size,
    ROUND(
          SUM(data_uncompressed_bytes) / nullIf(SUM(data_compressed_bytes), 0),
          2
      )                                                AS compression_ratio,
    SUM(rows)                                        AS total_rows,
    COUNT()                                          AS part_count
FROM system.parts
WHERE active = 1
GROUP BY database, table, engine
ORDER BY SUM(data_compressed_bytes) DESC
LIMIT 30;
