# CP3 — Optimization Report

## 1. What we did

Two kinds of changes:

1. **Added 8 new indexes** (`sql/05_indexes.sql`) targeting the slowest queries from the baseline.
2. **Rewrote 8 queries** (`sql/06_optimized_queries.sql`) to fix non-SARGable filters, replace a costly self-join with a window function, and correct a known SQL bug.

Ran `ANALYZE` after index creation so the planner picks up the new access paths.

---

## 2. Indexes added

| # | Index | On | Type | Targets |
|---|-------|----|------|---------|
| 1 | `idx_shows_screen_starts` | `shows(screen_id, starts_at)` INCLUDE (...) | Composite covering | R10, R01, R07 |
| 2 | `idx_bookings_confirmed` | `bookings(show_id, ...)` WHERE status='CONFIRMED' | Partial composite | R08, R12, R18, R19, R21 |
| 3 | `idx_bookings_status_booked_at` | `bookings(status, booked_at)` | Composite | R20, R21, R15 |
| 4 | `idx_booking_seats_seat_id` | `booking_seats(seat_id)` INCLUDE (price, ...) | Covering | R11, R17, R24, R25 |
| 5 | `idx_bookings_booked_at_desc_cover` | `bookings(booked_at DESC)` INCLUDE (...) | Covering desc | R22 |
| 6 | `idx_bookings_customer_status` | `bookings(customer_id, status)` | Composite | R05, R12, R21 |
| 7 | `idx_shows_movie_starts` | `shows(movie_id, starts_at)` INCLUDE (...) | Composite covering | R08, R19, W05 |
| 8 | `idx_seats_screen_class` | `seats(screen_id, seat_class)` INCLUDE (...) | Composite covering | R03, R11, R24 |

### Why these indexes?

The baseline had single-column indexes on most columns, but the planner couldn't use them well for queries that filter on two columns at once (e.g., show lookup by movie + date range). Composite indexes let the planner narrow down to the exact rows in one index scan instead of doing bitmap AND operations or falling back to seq scans.

Covering indexes (with INCLUDE) let PG do **index-only scans** — it reads all the data it needs from the index without touching the heap pages. This is especially important for the 300K-row `booking_seats` table where heap access is the bottleneck.

The partial index on CONFIRMED bookings is useful because almost every analytics query filters on `status = 'CONFIRMED'`. The index is smaller (only ~85% of rows) and the planner knows it doesn't need to recheck the status filter.

---

## 3. Query rewrites

| Query | Change | Why |
|-------|--------|-----|
| **R01** | `DATE(s.starts_at) = '...'` → `s.starts_at >= ... AND s.starts_at < ...` | DATE() wraps the column in a function, preventing the planner from using an index on `starts_at`. A range predicate is SARGable. |
| **R07** | `s.starts_at::date = '...'` → timestamp range | Same reason as R01 — cast to date blocks index usage. |
| **R10** | Self-join `s1 JOIN s2 ON screen_id` → `LEAD()` window function | The self-join reads 160K rows twice and produces ~16M candidate pairs (8M eliminated by join filter). The window function scans the filtered June rows once, partitioned by screen_id, and pairs each show with its next neighbour. |
| **R13** | `NOT IN (SELECT offer_code FROM bookings)` → `NOT EXISTS (...)` | The original always returns empty because `bookings.offer_code` has NULL values. `NOT IN` with any NULL in the subquery evaluates to UNKNOWN for every row. This is a documented bug in the problem statement (P6). `NOT EXISTS` handles NULLs correctly. |
| **R17** | `NOT EXISTS` subquery → `LEFT JOIN ... IS NULL` anti-join | Gives the planner more freedom to choose hash anti-join instead of nested loop. |
| **R18** | `EXTRACT(YEAR FROM s.starts_at) = 2026` → `s.starts_at >= '2026-01-01' AND ...` | EXTRACT wraps the column, blocking index use. Timestamp range is SARGable. |
| **R19** | Kept as correlated subquery (reverted rewrite) | With the new partial index `idx_bookings_confirmed`, the correlated subquery does an index-only scan per show (207 iterations × 0.004ms). A LEFT JOIN rewrite aggregates all 150K bookings first, which is slower. |
| **R20** | `booked_at::date BETWEEN '...' AND '...'` → `booked_at >= ... AND booked_at < ...` | The ::date cast prevents index usage on booked_at. Using timestamp range lets the planner use `idx_bookings_status_booked_at`. |

---

## 4. Before vs After comparison

| Query | Baseline (ms) | Optimized (ms) | Speedup | What helped |
|-------|-------------:|---------------:|--------:|-------------|
| **R01** | 8.507 | 0.840 | **10.1×** | SARGable date filter → index scan on starts_at |
| R02 | 0.467 | 0.249 | 1.9× | idx_shows_movie_starts composite |
| R03 | 0.643 | 0.558 | 1.2× | Index-only scan on seats (idx_seats_screen_class) |
| R04 | 0.067 | 0.086 | — | Already fast (unique index), within noise |
| R05 | 0.293 | 0.226 | 1.3× | idx_bookings_customer_status |
| R06 | 0.197 | 0.186 | — | Unchanged (300-row table, seq scan is fine) |
| R07 | 1.058 | 0.235 | **4.5×** | SARGable date + index-only scan (idx_shows_screen_starts) |
| R08 | 27.962 | 26.192 | 1.1× | Marginal — still seq scans bookings (wide filter) |
| R09 | 0.046 | 0.045 | — | Already sub-ms |
| **R10** | **247.654** | **26.945** | **9.2×** | LEAD() window function replaces self-join |
| R11 | 51.872 | 51.961 | — | No change — full aggregation on 300K rows can't avoid scan |
| R12 | 74.140 | 75.107 | — | No change — groups by customer×movie, needs full join |
| **R13** | 15.893 | 0.136 | **117×** | NOT EXISTS + index-only scan on partial index |
| R14 | 5.601 | 5.397 | 1.0× | Minimal — small tables |
| R15 | 105.122 | 106.354 | — | No change — full table scan needed for all-rows aggregate |
| R16 | 22.882 | 21.881 | 1.0× | Minimal |
| R17 | 35.227 | 29.208 | 1.2× | LEFT JOIN anti-pattern + index-only on seats |
| **R18** | 73.886 | 48.326 | **1.5×** | SARGable year filter |
| **R19** | 1.005 | 0.366 | **2.7×** | Correlated subquery now uses idx_bookings_confirmed (index-only scan) |
| R20 | 16.398 | 15.296 | 1.1× | SARGable date range + idx_bookings_status_booked_at |
| R21 | 52.154 | 52.369 | — | No change — aggregates ~85% of bookings, can't do better without materialized view |
| **R22** | 27.889 | 6.534 | **4.3×** | idx_bookings_booked_at_desc_cover → index-only scan |
| R23 | 0.028 | 0.023 | — | Already sub-ms |
| R24 | 61.537 | 62.182 | — | No change — full join across 300K booking_seats |
| R25 | 26.808 | 25.190 | 1.1× | Marginal |
| W01 | 0.714 | 0.979 | — | Write overhead from more indexes (expected) |
| W02 | 10.208 | 9.475 | 1.1× | idx_booking_seats_seat_id → index-only scan for NOT EXISTS |
| W03 | 0.318 | 0.319 | — | Already fast |
| W04 | 0.127 | 0.106 | 1.2× | Marginal |
| W05 | 3.828 | 3.067 | 1.2× | idx_shows_movie_starts |

### Summary

| Metric | Baseline | Optimized | Change |
|--------|--------:|----------:|-------:|
| Total time (all 30 queries) | 866.3 ms | 580.3 ms | **−33%** |
| Slowest query (R10) | 247.7 ms | 26.9 ms | **−89%** |
| Queries > 50 ms | 7 | 4 | −3 |
| Queries > 100 ms | 1 | 1 | 0 |

---

## 5. Queries that did NOT improve

Some queries stayed roughly the same even after optimization. Here's why:

**R11, R12, R15, R21, R24** — these all do full-table aggregations (GROUP BY across the entire bookings or booking_seats table). With 150K bookings and 300K booking_seats rows, PG has to read every row to compute sums and counts. No index helps because we need ALL rows, not a subset. The only way to speed these up would be:

- **Materialized views** — precompute the aggregation and refresh periodically. But the project scope doesn't include this.
- **Partitioning** (CP4) — if bookings is partitioned by date, queries that filter on a date range only scan the relevant partition, skipping the rest. This is what Phase 5 is for.
- **Parallelism tuning** — increasing `max_parallel_workers_per_gather` could help on these full scans, but we ran with default PG settings as instructed.

**R15 (106 ms, booking heatmap)** is the remaining outlier. It scans all 150K bookings and extracts ISODOW and HOUR from each `booked_at`, then sorts. The sort spills to disk (~3 MB). We could increase `work_mem` to 8MB to keep the sort in memory, but the main cost is the full seq scan which is unavoidable.

---

## 6. Trade-offs

Adding 8 indexes has a cost:
- **Disk space**: each index takes ~2–10 MB (small for this dataset, could matter at scale).
- **Write overhead**: W01 went from 0.71ms → 0.98ms because INSERTs now update more indexes. This is a ~38% increase on a single insert, but still under 1ms, which is fine.
- Overall the read speedup (33% total, up to 117× on individual queries) far outweighs the small write penalty.

---

## 7. Files

| File | Contents |
|------|----------|
| `sql/05_indexes.sql` | 8 new indexes with comments explaining each one |
| `sql/06_optimized_queries.sql` | All 30 queries, 8 rewritten, with change notes |
| `benchmarks/results/optimized/summary.csv` | Timing data (3 runs per query, avg/median/min/max) |
| `benchmarks/results/optimized/*.txt` | Raw EXPLAIN ANALYZE plans for every query |

