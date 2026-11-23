# Phase 5: Scalability Report (large dataset, 20×)

> **Status:** design sections complete. The large-dataset benchmark run is in progress; the
> "Optimized on large" column is filled only from `benchmarks/results/large/summary.csv` once the run
> finishes. No number in this report is estimated.

## 0. How the large run is done

```bash
createdb bms_large
psql -d bms_large -f sql/01_schema.sql
psql -d bms_large -f sql/02_load_data.sql      # folder changed seed_data/ -> large_data/ only
psql -d bms_large -f sql/05_indexes.sql
psql -d bms_large -c "VACUUM ANALYZE;"
./benchmarks/run_benchmark.sh bms_large large 5 sql/06_optimized_queries.sql
```

Only the **optimized** queries are run on the large data (never the original 30).

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

(Large row counts = `wc -l` of each CSV minus the header.)

---

## 1. Results table

Seed numbers are the averages from `benchmarks/results/optimized/summary.csv`.

| Query | Group | Target | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what we changed |
|-------|-------|-------:|-----------------------:|------------------------:|----------------------:|:-------------:|-------------------------|
| R01 | Interactive | 250 | 0.840 | | | | |
| R02 | Real-time | 5 | 0.249 | | | | |
| R03 | Real-time | 5 | 0.558 | | | | |
| R04 | Real-time | 5 | 0.086 | | | | |
| R05 | Real-time | 5 | 0.226 | | | | |
| R06 | Real-time | 5 | 0.186 | | | | |
| R07 | Interactive | 250 | 0.235 | | | | |
| R08 | Report | 5000 | 26.192 | | | | |
| R09 | Real-time | 5 | 0.045 | | | | |
| R10 | Report | 5000 | 26.945 | | | | |
| R11 | Report | 5000 | 51.961 | | | | |
| R12 | Report | 5000 | 75.107 | | | | |
| R13 | Interactive | 250 | 0.136 | | | | |
| R14 | Report | 5000 | 5.397 | | | | |
| R15 | Report | 5000 | 106.354 | | | | |
| R16 | Report | 5000 | 21.881 | | | | |
| R17 | Interactive | 250 | 29.208 | | | | |
| R18 | Report | 5000 | 48.326 | | | | |
| R19 | Report | 5000 | 0.366 | | | | |
| R20 | Report | 5000 | 15.296 | | | | |
| R21 | Report | 5000 | 52.369 | | | | |
| R22 | Interactive | 250 | 6.534 | | | | |
| R23 | Real-time | 5 | 0.023 | | | | |
| R24 | Report | 5000 | 62.182 | | | | |
| R25 | Report | 5000 | 25.190 | | | | |
| W01 | Real-time | 5 | 0.979 | | | | |
| W02 | Real-time | 5 | 9.475 | | | | |
| W03 | Real-time | 5 | 0.319 | | | | |
| W04 | Interactive | 250 | 0.106 | | | | |
| W05 | Interactive | 250 | 3.067 | | | | |

**Already a risk on seed data:** W02 (9.5 ms) is above the 5 ms real-time target *before* growing.
It must be fixed in this phase (see §3).

---

## 2. Growth analysis (expected classes — confirm with the large run)

The groups below follow from the plan shapes in `benchmarks/results/optimized/`. After the large run,
each query is moved into the class its measured growth actually shows.

### 2.1 Should stay about the same (≈1–3×) — index lookups grow with log n
R02, R03, R04, R05, R09, R13, R19, R23, W01, W03, W04, W05.
Plans are Index Scan / Index Only Scan on `uq_bookings_code`, `uq_customers_phone`, `pk_booking_seats`,
`idx_bookings_status`, `idx_shows_movie_starts`, `idx_bookings_confirmed`. A B-tree is 3–4 levels deep at
both sizes, and each query returns a *fixed* number of rows (one booking, one customer, one show's seats).

### 2.2 Should grow about 20× — they read a fixed **share** of a table
R08, R11, R12, R14, R15, R16, R18, R20, R21, R24, R25.
Plans contain Seq Scans on `bookings` / `booking_seats` or ranges that cover a fixed share of rows
(a whole month, a whole weekend, every row). 20× the rows → ≈20× the work.
Even at 20×, seed times of 5–106 ms project to roughly 0.1–2.1 s, inside the 5,000 ms report target —
but R15 (106 ms seed) is the one to watch.

### 2.3 Risk of growing **more than 20×** — problems that appear only at scale
| Query | Why it can grow faster than the data |
|-------|---------------------------------------|
| R22 | `OFFSET 100000` must walk 100,000 index entries at any size, but on large data the visibility map is less complete after loading, so the Index Only Scan does heap fetches unless `VACUUM` runs. Keyset pagination removes the problem. |
| R01, R07 | The city / venue has 20× more shows per day; small nested loops turn into many more probes. |
| R10 | Self-join of shows per screen: the number of shows *per screen* does not grow (20× screens), but sorting by `gap` grows to a sort that may spill past `work_mem` → external merge on disk. |
| R17 | NOT EXISTS anti-join over `booking_seats` for a whole month; at 6M rows the hash table may exceed `work_mem` and spill. |
| R11, R24 | Hash join of 6M `booking_seats` with 1.9M `seats`: the hash on `seats` (≈1.9M rows) may no longer fit in memory → multi-batch hash join. |
| W02 | Already 9.5 ms on seed; works on the whole screen's seat list for the oldest pending booking. |

---

## 3. What broke at scale and how we fix it

Fill each row with the **before / after plan** from `benchmarks/results/large/` after the run.
The fixes planned for the likely failures:

| Query | Expected symptom in the large plan | Fix (no server-setting tricks) |
|-------|-----------------------------------|--------------------------------|
| W02 | > 5 ms even on seed | Rewrite the oldest-pending lookup as `ORDER BY booking_id LIMIT 1` on the partial index `WHERE status = 'PENDING'`; walk `seats` by `idx_seats_screen_class` and probe `pk_booking_seats` with a `NOT EXISTS` that stops after 2 rows. |
| R22 | Heap Fetches > 0 in Index Only Scan, time grows | `VACUUM bookings` (visibility map) and switch to keyset pagination: `WHERE booked_at < :last_seen ORDER BY booked_at DESC LIMIT 25`. *Last-seen value on the large data:* the `booked_at` of row 100,000 in descending order (the last row of page 4,000), taken once with the same query and passed in as a parameter — exactly the value the console would hold from the previous page. Ties on `booked_at` are handled by `(booked_at, booking_id) < (:ts, :id)`. |
| R15 | Seq Scan over 3M bookings + HashAggregate | Report query, reads every row by definition. If above target: covering index on `bookings (booked_at)` for an Index Only Scan, or a summary table `booking_hour_stats` refreshed nightly. |
| R11, R24 | Multi-batch Hash Join on seats | Covering index `seats (seat_id) INCLUDE (screen_id, seat_class)` so the seat side is an Index Only Scan, or a materialized view of revenue per (screen_type / city, seat_class) refreshed nightly. |
| R17 | Anti-join spills | Index on `booking_seats (seat_id, show_id)` so the NOT EXISTS probes per seat instead of hashing the month. |
| R10 | External merge sort | Uses `idx_shows_screen_starts`; if the sort still spills, use `lead()` over `(PARTITION BY screen_id ORDER BY starts_at)` — one pass instead of a self-join. |

Every rewrite is checked for **identical results** (row count + `EXCEPT` both ways) exactly as in Phase 4.

---

## 4. Storage

Run on both databases and paste the output:

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;

SELECT relname,
       pg_size_pretty(pg_table_size(relid))   AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS index_size,
       round(100.0 * pg_indexes_size(relid) / nullif(pg_table_size(relid),0), 1) AS index_pct
FROM pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

| | Seed | Large |
|---|---:|---:|
| Raw CSV size | 8.8 MB zipped | 882 MB unzipped (190 MB zipped) |
| Total database size | | |
| Table data | | |
| Indexes | | |
| Largest table (`bookings`) table / index | | |
| `booking_seats` table / index | | |

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

Fill after the large run. Template:

- Targets met: __ of 30. Queries that needed a scale-only fix: __.
- Ready for next year (20×): yes / no, because …
- Remaining risks:
  1. W02 seat-lock path is the tightest real-time query (9.5 ms already on seed).
  2. Full-table analytics (R11, R15, R24) grow linearly; at 100× they need materialized views.
  3. Hash joins on `seats` / `booking_seats` can spill to disk at 100× without the covering indexes.
  4. Partitioning `bookings` changes the uniqueness of `booking_code` — needs a design decision first.
