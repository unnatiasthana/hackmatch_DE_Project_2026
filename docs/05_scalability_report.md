# Phase 5: Scalability Report (large dataset, 20×)

> **Status:** large-dataset run complete. Every number in §1–§4 is measured, taken from
> `benchmarks/results/large/summary.csv` and the raw plans next to it. No number is estimated.
> **Result: 29 of 30 queries met their target on the first run; R17 missed and was fixed (§3).**

## 0. How the large run is done

```bash
createdb bms_large
psql -d bms_large -f sql/01_schema.sql
sed 's#seed_data/#large_data/#g' sql/02_load_data.sql | psql -d bms_large   # folder name changed only
psql -d bms_large -f sql/05_indexes.sql
psql -d bms_large -c "VACUUM ANALYZE;"
./benchmarks/run_benchmark.sh bms_large large 3 sql/06_optimized_queries.sql
```

Only the **optimized** queries are run on the large data (never the original 30). Each query runs 3 times
and the table reports the **average**, as the checkpoint rules require. Write queries run inside
`BEGIN … ROLLBACK`, so the data is unchanged between runs.

**Machine:** Apple M4, 16 GB RAM, macOS 26.5, PostgreSQL 18.6 (Postgres.app), default settings
(`shared_buffers = 128MB`, `work_mem = 4MB`, `max_parallel_workers_per_gather = 2`).
Load time: 4 min 19 s for the CSVs, 19 s for the 8 indexes in `05_indexes.sql`, 2 s for `VACUUM ANALYZE`.

| Table | Seed rows | Large rows | Factor |
|-------|----------:|-----------:|-------:|
| shows | 160,034 | 3,201,268 | 20.0× |
| bookings | 150,094 | 3,004,077 | 20.0× |
| booking_seats | 300,389 | 6,016,946 | 20.0× |
| seats | 94,056 | 1,879,182 | 20.0× |
| customers | 40,000 | 800,000 | 20.0× |
| movie_reviews | 32,510 | 651,398 | 20.0× |
| movies | 300 | 6,000 | 20.0× |
| screens | 490 | 9,800 | 20.0× |
| venues | 140 | 2,800 | 20.0× |

(Large row counts are `SELECT count(*)` on the loaded database; they equal `wc -l` of each CSV minus the header.)

---

## 1. Results table

"Optimized on seed" is the Phase 4 average from `benchmarks/results/optimized/summary.csv`.
"Optimized on large" is the average from `benchmarks/results/large/summary.csv`.
Targets: real-time **< 5 ms**, interactive **< 250 ms**, reports **< 5,000 ms**.

| Query | Group | Target (ms) | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what we changed |
|-------|-------|------------:|-----------------------:|------------------------:|----------------------:|:-------------:|-------------------------|
| R01 | Interactive | 250 | 0.840 | 9.336 | 11.1× | Yes | |
| R02 | Real-time | 5 | 0.249 | 0.749 | 3.0× | Yes | |
| R03 | Real-time | 5 | 0.558 | 0.256 | 0.5× | Yes | |
| R04 | Real-time | 5 | 0.086 | 0.197 | 2.3× | Yes | |
| R05 | Real-time | 5 | 0.226 | 0.193 | 0.9× | Yes | |
| R06 | Real-time | 5 | 0.186 | 2.188 | 11.8× | Yes | |
| R07 | Interactive | 250 | 0.235 | 0.370 | 1.6× | Yes | |
| R08 | Report | 5,000 | 26.192 | 163.793 | 6.3× | Yes | |
| R09 | Real-time | 5 | 0.045 | 0.398 | 8.8× | Yes | |
| R10 | Report | 5,000 | 26.945 | 467.668 | 17.4× | Yes | |
| R11 | Report | 5,000 | 51.961 | 889.646 | 17.1× | Yes | |
| R12 | Report | 5,000 | 75.107 | 1,469.153 | 19.6× | Yes | |
| R13 | Interactive | 250 | 0.136 | 1.011 | 7.4× | Yes | |
| R14 | Report | 5,000 | 5.397 | 44.414 | 8.2× | Yes | |
| R15 | Report | 5,000 | 106.354 | 280.593 | 2.6× | Yes | |
| R16 | Report | 5,000 | 21.881 | 393.198 | 18.0× | Yes | |
| **R17** | Interactive | 250 | 29.208 | **544.191** | 18.6× | **No** | Rewrote the LEFT JOIN / DISTINCT anti-join back to a per-seat `NOT EXISTS` (§3.1). **After fix: 2.515 ms** on large (avg of 7.124, 0.221, 0.201), 0.231 ms on seed. |
| R18 | Report | 5,000 | 48.326 | 741.601 | 15.3× | Yes | |
| R19 | Report | 5,000 | 0.366 | 9.197 | 25.1× | Yes | |
| R20 | Report | 5,000 | 15.296 | 98.406 | 6.4× | Yes | |
| R21 | Report | 5,000 | 52.369 | 3,427.674 | 65.5× | Yes | Meets target, but grew far faster than the data; see §3.2. |
| R22 | Interactive | 250 | 6.534 | 7.877 | 1.2× | Yes | |
| R23 | Real-time | 5 | 0.023 | 0.217 | 9.4× | Yes | |
| R24 | Report | 5,000 | 62.182 | 1,097.198 | 17.6× | Yes | |
| R25 | Report | 5,000 | 25.190 | 239.659 | 9.5× | Yes | |
| W01 | Real-time | 5 | 0.979 | 2.090 | 2.1× | Yes | |
| W02 | Real-time | 5 | 9.475 | 1.334 | 0.1× | Yes | Was over target on seed; on large the planner chose a better plan by itself (§3.3). |
| W03 | Real-time | 5 | 0.319 | 0.991 | 3.1× | Yes | |
| W04 | Interactive | 250 | 0.106 | 2.932 | 27.7× | Yes | |
| W05 | Interactive | 250 | 3.067 | 10.335 | 3.4× | Yes | |

**Targets met: 29 of 30 on the first run, 30 of 30 after the R17 fix.**

> **Reading the growth column.** The Phase 4 seed numbers were measured on a different laptop
> (PostgreSQL 15). To check that the growth comes from the data and not from the machine, we also ran
> the same `06_optimized_queries.sql` on a seed copy (`bms_seed`) on **this** machine. The two seed runs
> agree closely (e.g. R11 52.0 vs 46.8 ms, R12 75.1 vs 74.1 ms, W02 9.5 vs 9.4 ms), so the growth column
> is a fair comparison. §2 uses the same-machine **median** growth, because many sub-millisecond queries
> have a slow first (cold-cache) run that inflates their average. For example, R04 runs
> 0.541 / 0.025 / 0.026 ms on large: the average is 0.197 ms, but the warm runs are the same as on seed.

---

## 2. Growth analysis (measured)

Growth = large ÷ seed, both measured on the same machine, using the median of 3 runs.

### 2.1 Stayed about the same (≤ 2×): index lookups grow with log n
**R02, R03, R04, R05, R07, R13, R19, R22, R23, W01, W03, W05** (0.5× – 1.8×).

These plans are Index Scans or Index Only Scans that return a *fixed* number of rows: one booking by
code (R04 on `uq_bookings_code`), one customer by phone (R23 on `uq_customers_phone`), one show's seat
map (R03 on `shows_pkey` + `idx_seats_screen_class`), one customer's bookings (R05 on
`idx_bookings_customer_status`). A B-tree is 3–4 levels deep at both sizes, so 20× the rows adds at most
one page read per lookup.
- **R22** (`OFFSET 100000 LIMIT 25`) is in this group because it always walks 100,025 entries of
  `idx_bookings_booked_at_desc_cover`, whatever the table size. The plan is an Index Only Scan with
  **Heap Fetches: 0**, so the visibility-map risk predicted in Phase 4 did not appear (we ran
  `VACUUM ANALYZE` after the load).
- **R19** has an average of 9.2 ms, but that comes from one cold run (26.5 ms); the warm runs are 0.54 ms.

### 2.2 Grew less than 20× (6–11×): fixed share, but cheaper per row at scale
**R08 (9.3×), R09 (7.8×), R14 (9.6×), R15 (6.6×), R20 (9.5×), R25 (10.9×), W04 (6.2×).**

- R08, R14, R15, R20 and R25 read a fixed share of `bookings`, `movie_reviews` or `booking_seats`, so their work
  grows 20×. Their *time* grows less because on seed a large part of the time is fixed start-up cost.
  On large, the parallel workers (`Gather`, 2 workers) pay off, and R15 becomes a
  **Parallel Index Only Scan** on `idx_bookings_booked_at` with 0 heap fetches.
- R09 and W04 scan `idx_bookings_status` for `status = 'PENDING'`. There are 193 pending bookings on large
  vs 10 on seed, so these grow with the number of pending rows, not with log n. At 0.27 ms and 0.62 ms
  warm they are still far below target.

### 2.3 Grew about 20× (15–24×): they read a fixed share of a large table
**R01 (15.5×), R06 (18.4×), R10 (23.9×), R11 (19.1×), R12 (21.9×), R16 (19.1×), R17 (16.9×), R18 (18.5×), R24 (16.3×).**

These plans contain Seq Scans on `bookings`, `booking_seats`, `seats` or `movies`, or index ranges
that cover a fixed share of rows (a whole month of shows, one city's shows for a day while the number of
cities stays at 10). 20× the rows → ≈ 20× the work.
- **R11, R24** (revenue by seat class) now run **multi-batch hash joins** of `booking_seats` with
  `seats`: `Batches: 16`, about 31k temp blocks written. **R12** spills too (`Batches: 32/33`). This is the
  Phase 4 prediction coming true: the hash table no longer fits in `work_mem = 4MB`. They still take
  only 0.9–1.5 s against the 5 s target.
- **R10** stays an Index Only Scan on `idx_shows_screen_starts` plus a `WindowAgg`, with the sort in memory
  (`quicksort 506kB`). It does not spill, so it grows linearly.
- **R17** belongs here, and that is why it failed: an interactive query should not read a share of the
  whole table (§3.1).

### 2.4 Grew more than 20×: a problem that only appears at scale
**R21 (82×)**: see §3.2.

### 2.5 Got faster at scale
**W02 (0.1×)**: the planner picked a different plan on the large statistics (§3.3).

---

## 3. What broke at scale and how we fixed it

### 3.1 R17: missed target (544 ms vs 250 ms), fixed to 2.5 ms

**Why it broke.** In Phase 4 we rewrote R17's `NOT EXISTS` as a `LEFT JOIN` to
`SELECT DISTINCT seat_id … WHERE starts_at in June`. That subquery does not depend on screen 101, so
PostgreSQL computes it for **every screen in the country** before keeping 40 seats.
Before plan (`benchmarks/results/large/R17.txt`, run 3):

```
Sort  (actual time=510.163..533.588 rows=27)
  ->  Hash Right Anti Join  (Hash Cond: bs.seat_id = se.seat_id)
        ->  HashAggregate  (Group Key: bs.seat_id)  rows=115,439
              ->  Gather (2 workers)  rows=283,410
                    ->  Parallel Hash Join  (bs.show_id = s.show_id)  rows=734,491 × 3 loops
                          ->  Parallel Seq Scan on booking_seats bs   rows=2,005,649 × 3 loops
                          ->  Parallel Hash  Batches: 8  (temp written=2540)
                                ->  Parallel Index Scan using idx_shows_starts_at on shows s
        ->  Hash
              ->  Index Only Scan using idx_seats_screen_class on seats se  rows=40
Buffers: shared hit=85,099 read=37,795, temp read=23,107 written=23,156
Execution Time: 533.749 ms
```

It reads all 6M `booking_seats` rows and joins 2.2M June bookings, then throws away all but 40 seats.
On seed the same work was 300k rows, so it cost only 29 ms and the problem was hidden.

**Fix.** Probe only the 40 seats of screen 101: a correlated `NOT EXISTS` driven by the seat. No new
index is needed. `idx_booking_seats_seat_id (seat_id) INCLUDE (price, show_id, booking_id)` from
`05_indexes.sql` already covers the probe. The change is applied in `sql/06_optimized_queries.sql`.

```sql
SELECT se.seat_id, se.row_label, se.seat_number, se.seat_class
FROM seats se
WHERE se.screen_id = 101
  AND NOT EXISTS (
        SELECT 1
        FROM booking_seats bs
        JOIN shows s ON s.show_id = bs.show_id
        WHERE bs.seat_id = se.seat_id
          AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01')
ORDER BY se.row_label, se.seat_number;
```

After plan (`benchmarks/results/large/R17_after_fix.txt`, run 3):

```
Sort  (actual time=0.169..0.170 rows=27)
  ->  Nested Loop Anti Join
        ->  Index Only Scan using idx_seats_screen_class on seats se   rows=40, Heap Fetches: 0
        ->  Nested Loop   (loops=40)
              ->  Index Only Scan using idx_booking_seats_seat_id on booking_seats bs   rows=0.72 × 40 loops, Heap Fetches: 0
              ->  Index Scan using shows_pkey on shows s   (Filter: starts_at in June)  29 loops
Buffers: shared hit=247
Execution Time: 0.201 ms
```

| | Run 1 | Run 2 | Run 3 | Average |
|---|---:|---:|---:|---:|
| R17 before, large (ms) | 559.205 | 539.619 | 533.749 | **544.191** |
| R17 after, large (ms) | 7.124 | 0.221 | 0.201 | **2.515** |
| R17 after, seed (ms) | 0.309 | 0.186 | 0.197 | 0.231 |

From 123k buffers + 23k temp blocks down to 247 buffers. The work now depends on the number of seats in
one screen (about 40) and the bookings of those seats, not on the size of `booking_seats`, so it moves
into the "stays the same" group (§2.1).

**Same result check.** On `bms_large`, old and new R17 both return 27 rows, and `old EXCEPT new` and
`new EXCEPT old` both return 0 rows.

**Lesson.** The Phase 4 comment said the LEFT JOIN "lets the planner use a hash anti-join instead of a
nested loop". That is only a win when the outer side is large. Here the outer side is 40 seats, so the
nested-loop anti-join with an index probe is the right plan at every data size.

### 3.2 R21: meets target, but grew 82×

R21 (top 20 customers by confirmed bookings since 1 Jan) takes 3,421–3,442 ms on every run, so it is not
a cold-cache effect. The plan is:

```
Limit -> Sort (top-N heapsort) -> GroupAggregate
  -> Index Scan using idx_bookings_customer_status on bookings  rows=2,671,876
```

The planner uses `idx_bookings_customer_status (customer_id, status)` to get rows already grouped by
customer. But the index does not hold `booked_at` or `total_amount`, so it makes 2.67M **random** heap
visits in `customer_id` order across a 338 MB table. On seed the table (17 MB) sits in memory, so the
random order is nearly free. At 20× it is not, and the cost grows faster than the data.

For comparison, the same query with a sequential scan (`SET enable_indexscan = off`, for diagnosis only)
runs in **1,020–1,303 ms** (Seq Scan + HashAggregate). We did not change R21 because it meets its 5 s
target. The fix if it grows further is a covering partial index, so the plan becomes an Index Only Scan:

```sql
CREATE INDEX idx_bookings_confirmed_customer
    ON bookings (customer_id) INCLUDE (booked_at, total_amount)
    WHERE status = 'CONFIRMED';
```

or a nightly `customer_spend` summary table for the loyalty report.

### 3.3 W02: over target on seed, fine on large

W02 (lock 2 seats for the oldest pending booking) was 9.5 ms on seed, already above the 5 ms target.
On seed the plan walks `seats_pkey` in `seat_id` order (63,729 rows) to find two seats of the right
screen for `ORDER BY seat_id LIMIT 2`. On large, the statistics make the planner fetch the screen's 40
seats through `idx_seats_screen_class` and sort them: 0.50–0.52 ms warm, **1.334 ms average**. So W02
meets its target on large, but its plan depends on statistics. Making the seat lookup explicit (filter
`seats` by `screen_id` in a subquery before `ORDER BY … LIMIT 2`) would make it fast on both sizes.

### 3.4 Phase 4 predictions vs what happened

| Query | Predicted problem | What the large plan shows |
|-------|-------------------|---------------------------|
| W02 | > 5 ms | 1.3 ms; a better plan was chosen on large stats (§3.3). |
| R22 | Heap fetches in Index Only Scan | Heap Fetches: 0; 7.9 ms, 1.1× growth. |
| R15 | Seq Scan + HashAggregate near target | Parallel Index Only Scan, 281 ms; far below 5 s. |
| R11, R24 | Multi-batch hash join on `seats` | Confirmed: `Batches: 16`, temp spill; 0.9–1.1 s, still within target. |
| R17 | Anti-join spill | Confirmed and worse: it reads the whole month for all screens; **fixed** (§3.1). |
| R10 | External merge sort | Did not happen: in-memory quicksort (506 kB) on `idx_shows_screen_starts`. |
| R21 | Not predicted | Random heap access through a non-covering index: 82× (§3.2). |

Every rewrite is checked for **identical results** (row count + `EXCEPT` both ways) exactly as in Phase 4.

---

## 4. Storage

Measured with the queries below on both databases (same machine, after `05_indexes.sql` and `VACUUM ANALYZE`):

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;

SELECT relname,
       pg_size_pretty(pg_table_size(relid))   AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS index_size,
       round(100.0 * pg_indexes_size(relid) / nullif(pg_table_size(relid),0), 1) AS index_pct
FROM pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

| | Seed | Large | Growth |
|---|---:|---:|---:|
| Raw CSV size | 41 MB unzipped (8.8 MB zipped) | 882 MB unzipped (190 MB zipped) | 21× |
| Total database size | 184 MB | 3,367 MB | 18.3× |
| Table data (`bms` schema) | 55 MB | 1,061 MB | 19.3× |
| Indexes (`bms` schema) | 121 MB | 2,297 MB | 19.0× |
| `bookings` table / index | 17 MB / 43 MB (252%) | 338 MB / 732 MB (217%) | 20× / 17× |
| `shows` table / index | 11 MB / 37 MB (338%) | 212 MB / 736 MB (347%) | 19× / 20× |
| `booking_seats` table / index | 15 MB / 26 MB (169%) | 300 MB / 521 MB (174%) | 20× / 20× |
| `seats` table / index | 5.0 MB / 8.4 MB (170%) | 94 MB / 166 MB (177%) | 19× / 20× |

Indexes are about **2.2× the size of the table data** at both sizes, so storage grows linearly. The biggest
index cost is on `shows` (347% of the table), mainly the covering `idx_shows_screen_starts … INCLUDE (…)`
and `idx_shows_movie_starts`. At 100× that is about 3.7 GB of indexes on `shows` alone. It is the first
place to look if disk becomes a constraint, e.g. dropping columns from `INCLUDE` that only one report
needs.

---

## 5. Architecture for 100×

At 100× we would hold ≈15M bookings, ≈30M booking seats, ≈16M shows and ≈9.4M seats.

### 5.1 Partitioning

**Table:** `booking_seats`, **method:** `HASH (show_id)`, 16 partitions. DDL: [`sql/08_partitioning.sql`](../sql/08_partitioning.sql).

- **Why show_id:** every real-time access (R03, R07, R25, W01, W02, W04) filters or joins on `show_id`,
  so the planner prunes to exactly one partition. At 100×, each partition holds ≈1.9M rows instead of 30M.
- **Why HASH, not RANGE:** `booking_seats` has no timestamp column; HASH spreads a release-weekend's writes
  across all partitions instead of one hot partition.
- **Primary-key rule:** a PK / UNIQUE constraint on a partitioned table must include all partition-key
  columns. `PRIMARY KEY (show_id, seat_id)` contains `show_id`, so the *seat sold only once per show*
  guarantee stays global. Partitioning by `booking_id` would make this PK impossible.
- **Pruning proof:** `EXPLAIN` of R03 at the end of `08_partitioning.sql` — paste the plan here, it must
  list a single `booking_seats_pNN`.
- **Second candidate:** `bookings` by `RANGE (booked_at)` monthly, which lets R15, R20, R21 prune to the
  months they read and makes archiving a `DETACH PARTITION`. Cost: its PK would become
  `(booking_id, booked_at)`, and `booking_code` uniqueness could no longer be a global constraint
  (it must include `booked_at`) — so we keep `bookings` unpartitioned until 100× is real.

### 5.2 Sharding

**Shard key: city (`venues.city_id`).**
- A booking touches one show → one screen → one venue → one city, so the whole booking path
  (R02, R03, R05 for a home-city user, R09, W01–W04) runs on a single shard with local transactions —
  no distributed locks for the seat-lock guarantee.
- 10 cities make a manageable shard count; Mumbai/Bengaluru can get their own shards, smaller cities share.
- *Why not by show:* a customer's "My bookings" (R05) and support lookups would scatter across every shard.
  *Why not by venue:* too many shards (2,800 venues on large data) and city pages (R01, R02) would fan out.

**Cross-shard queries** (span all cities): R08 box office, R11, R12, R14 ratings, R15, R18 regional
collections, R20, R21 loyalty, R24, R13 offers, R22 support console, R04 lookup by code, R23 sign-in.
Handling:
- Reference tables (`movies`, `offers`, `cities`) are replicated to every shard.
- `customers` live in a global user service; R23 sign-in and R04 code lookup use a global lookup table
  (`booking_code → city shard`).
- Reports run as scatter-gather (each shard aggregates, coordinator merges sums/counts), or better,
  from a central analytics copy fed by logical replication / nightly ETL.

### 5.3 Read replicas and caching

| Send to | Queries | Reason |
|---------|---------|--------|
| **Primary only** | R03, R09, W01, W02, W03, W04, W05 | Seat availability and payment state must be current; a stale replica can sell the same seat twice. |
| **Read replica** | R05, R07, R17, R22, R25, R04 | Read-only, a few seconds of lag is acceptable for support and cinema managers. |
| **Replica + report schedule / materialized views** | R08, R10, R11, R12, R14, R15, R16, R18, R19, R20, R21, R24 | Heavy analytics; must never compete with checkout on the primary. |
| **Cache (app-side, short TTL)** | R01, R02, R06, R13, R23 | Now-showing, showtimes and search are the same for every user in a city and change only when the schedule changes; the Friday-morning spike (P1) is served from cache. |

### 5.4 Maintenance

- **`booking_seats` autovacuum:** W04 deletes expired seat locks all day, so dead tuples pile up.
  Per partition: `autovacuum_vacuum_scale_factor = 0.02`, `autovacuum_analyze_scale_factor = 0.01`
  (set in `08_partitioning.sql`) — vacuum after 2% changes instead of the default 20%.
- **`bookings`:** same lower scale factors; regular VACUUM keeps the visibility map fresh so R22 and
  R19 stay Index Only Scans with 0 heap fetches.
- **Archiving:** shows older than 6 months (and their bookings / booking seats) move to an archive
  table or cold storage; with RANGE-partitioned `bookings` this is `DETACH PARTITION`.
- **Summary tables / materialized views:** refreshed nightly with `REFRESH MATERIALIZED VIEW CONCURRENTLY`
  (needs a unique index), box-office (R08) every 15 minutes during release weekends.
- **ANALYZE** after every bulk load, and `pg_stat_statements` to spot new slow queries.

---

## 6. Conclusion

- **Targets met: 29 of 30 on the first large run, 30 of 30 after the fix.**
  Queries that needed a scale-only fix: **R17** (544 ms → 2.5 ms, a rewrite back to per-seat `NOT EXISTS`, no new index).
- **Ready for next year (20×): yes.** Every real-time query is under 2.2 ms on average (the slowest is R06, a Seq Scan of `movies`).
  Every interactive query is under 11 ms after the R17 fix, and the slowest report (R21) takes 3.4 s against a 5 s target.
  Storage grows linearly (3.4 GB total, indexes ≈ 2.2× table data).
- **Remaining risks:**
  1. **R21** grows faster than the data (82×) because of random heap access through a non-covering index.
     At 100× it would pass 5 s. Fix ready: a covering partial index on `bookings (customer_id) INCLUDE (booked_at, total_amount) WHERE status = 'CONFIRMED'` (§3.2).
  2. **W02**'s good plan on large depends on statistics; on seed the same query takes 9.5 ms. Make the
     per-screen seat lookup explicit so the plan cannot flip back (§3.3).
  3. **Full-table analytics** (R11, R12, R16, R18, R24) grow linearly and R11, R12, R24 already spill to disk
     (multi-batch hash joins). At 100× they need nightly materialized views or the `booking_seats`
     partitioning in §5.1.
  4. **R06** (title search `ILIKE '%kalki%'`) is a Seq Scan of `movies`: 2.17 ms on 6,000 movies, growing 18×.
     At 100× (30,000 movies) it would be around 11 ms, over the 5 ms real-time target. A leading-wildcard `ILIKE`
     cannot use a B-tree; the fix is a trigram index (`CREATE EXTENSION pg_trgm; CREATE INDEX … USING gin (title gin_trgm_ops)`)
     or serving search from the app cache (§5.3).
  5. Partitioning `bookings` changes the uniqueness of `booking_code`; that needs a design decision first.
