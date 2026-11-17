# CP2 — Baseline Query Timings

## Setup

- **Machine:** MacBook Pro M4, 16 GB RAM, macOS
- **PostgreSQL:** 15.20 (Homebrew), default config (shared_buffers = 128 MB, work_mem = 4 MB)
- **Data:** seed_data.zip loaded via `sql/02_load_data.sql` — all 11 tables, ~300K bookings, zero integrity violations

Row counts after loading:

| Table | Rows |
|-------|-----:|
| cities | 10 |
| venues | 140 |
| screens | 490 |
| seats | 94,056 |
| movies | 300 |
| shows | 160,034 |
| customers | 40,000 |
| offers | 25 |
| bookings | 150,094 |
| booking_seats | 300,389 |
| movie_reviews | 32,510 |

## How we ran the benchmark

Used the provided `benchmarks/run_benchmark.sh` script. Each query was run 3 times with `EXPLAIN (ANALYZE, BUFFERS)`, and the average execution time was recorded. Write queries were wrapped in `BEGIN; ... ROLLBACK;` so the data stays unchanged between runs.

```bash
./benchmarks/run_benchmark.sh bookmyshow baseline
```

ANALYZE was already done during data load so the planner had fresh stats.

## Timing Results

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Avg (ms) | Main scan type |
|-------|------|-------------|----------:|----------:|----------:|--------:|----------------|
| R01 | READ | Now-showing in city 3 with joins | 10.184 | 9.926 | 5.412 | 8.507 | Seq Scan on screens, venues; Index Scan on shows |
| R02 | READ | Showtimes for movie 5, next 7 days | 0.419 | 0.450 | 0.532 | 0.467 | Bitmap Heap Scan on shows |
| R03 | READ | Seat availability for show 144446 | 0.622 | 0.635 | 0.673 | 0.643 | Index Scan on shows, seats; Bitmap Heap on booking_seats |
| R04 | READ | Booking lookup by code | 0.057 | 0.060 | 0.084 | 0.067 | Index Scan (uq_bookings_code) |
| R05 | READ | My bookings for customer 1331 | 0.251 | 0.289 | 0.339 | 0.293 | Bitmap Heap Scan on bookings; Index Scans on joins |
| R06 | READ | Search movies by title substring | 0.191 | 0.197 | 0.204 | 0.197 | Seq Scan on movies |
| R07 | READ | Occupancy for venue 10, June 2026 | 0.983 | 0.988 | 1.202 | 1.058 | Index Scan on screens; Bitmap on shows; Index Only Scan on booking_seats |
| R08 | READ | Box office: total per movie, opening weekends | 24.267 | 27.553 | 32.065 | 27.962 | Seq Scan on bookings, movies |
| R09 | READ | Pending payment queue (oldest 10) | 0.043 | 0.046 | 0.048 | 0.046 | Index Scan (idx_bookings_status) |
| R10 | READ | Cleaning gap < 30 min between shows, June | 243.435 | 247.702 | 251.824 | 247.654 | Parallel Hash Join; Bitmap + Seq Scan on shows (self-join) |
| R11 | READ | Revenue breakdown by seat class, screen type | 51.790 | 51.862 | 51.965 | 51.872 | Seq Scan on booking_seats, seats, screens |
| R12 | READ | Monthly revenue trend (2026) | 73.165 | 74.480 | 74.776 | 74.140 | Seq Scan on shows, bookings |
| R13 | READ | Offers never redeemed (NOT EXISTS) | 15.670 | 15.726 | 16.282 | 15.893 | Seq Scan on offers, bookings |
| R14 | READ | Top 10 movies by avg audience rating | 5.526 | 5.621 | 5.657 | 5.601 | Seq Scan on movie_reviews, movies |
| R15 | READ | Booking heatmap: day-of-week × hour | 102.850 | 105.332 | 107.183 | 105.122 | Seq Scan on bookings; external merge sort (spills to disk) |
| R16 | READ | Revenue by payment method, per city, June | 22.437 | 22.504 | 23.704 | 22.882 | Seq Scan on bookings; Index Scan on shows |
| R17 | READ | Seats in screen 42 never sold in June | 34.889 | 35.125 | 35.668 | 35.227 | Index Scan on seats; Seq Scan on booking_seats |
| R18 | READ | Collections per language per city (2026) | 72.871 | 73.563 | 75.223 | 73.886 | Seq Scan on bookings, shows, movies, screens, venues |
| R19 | READ | Distributor: tickets sold per show, movie 2 June | 0.949 | 1.030 | 1.035 | 1.005 | Bitmap Heap Scan on shows, bookings |
| R20 | READ | Daily collections + running total, June | 16.208 | 16.384 | 16.603 | 16.398 | Seq Scan on bookings |
| R21 | READ | Top 20 customers by bookings (2026) | 51.427 | 51.966 | 53.069 | 52.154 | Index Scan (idx_bookings_customer_id) — full scan |
| R22 | READ | Support console pagination (OFFSET 100000) | 27.598 | 27.672 | 28.397 | 27.889 | Index Scan on bookings (booked_at) — scans 100K+ rows |
| R23 | READ | Sign-in by phone number | 0.025 | 0.025 | 0.035 | 0.028 | Index Scan (uq_customers_phone) |
| R24 | READ | Avg price per seat class per city | 60.762 | 61.438 | 62.411 | 61.537 | Seq Scan on booking_seats, seats, screens, venues |
| R25 | READ | Late-night show occupancy, June | 26.492 | 26.800 | 27.133 | 26.808 | Seq Scan on booking_seats; Index Scan on shows |
| W01 | WRITE | Insert PENDING booking | 0.703 | 0.719 | 0.721 | 0.714 | (direct insert) |
| W02 | WRITE | Seat lock: add 2 seats to oldest PENDING | 9.755 | 10.317 | 10.552 | 10.208 | Index Scans on bookings, seats, shows, booking_seats |
| W03 | WRITE | Confirm oldest PENDING booking | 0.271 | 0.322 | 0.361 | 0.318 | Index Scan (idx_bookings_status) |
| W04 | WRITE | Expire stale PENDING seat locks | 0.124 | 0.126 | 0.132 | 0.127 | Index Scan on bookings (status), booking_seats |
| W05 | WRITE | 10% price bump for July weekend shows | 3.507 | 3.671 | 4.305 | 3.828 | Bitmap Heap Scan on shows |

## Observations

### Fast queries (< 1 ms)

R04, R09, R23 are sub-millisecond because they hit unique or selective indexes (booking_code lookup, phone lookup, status = 'PENDING' which has very few rows). These are fine as-is and probably won't need optimization.

R02, R03, R05, R06, R07 are also under 1–2 ms — mostly because they filter to a small number of rows using existing indexes or small tables (movies only has 300 rows so seq scan is fine).

### Slow queries — the ones we need to fix

**R10 (247 ms)** — by far the slowest. It's the "cleaning gap" self-join on shows: for every pair of consecutive shows on the same screen in June, check if the gap is < 30 min. The planner does a Parallel Hash Join on the full shows table (self-join) with a time-range filter, then sorts. It's reading ~160K rows twice. We'll probably need a window function (LAG) to avoid the self-join, plus maybe a composite index on (screen_id, starts_at).

**R15 (105 ms)** — booking heatmap needs a full seq scan of bookings (150K rows), then extracts day-of-week and hour with EXTRACT, sorts by both columns, and the sort spills to disk (external merge, 2936 kB). Increasing work_mem or adding a covering index with the extracted fields might help here.

**R12 (74 ms), R18 (74 ms)** — both are multi-table aggregations joining bookings → shows → movies → venues. Full seq scans everywhere because there's no date filter that can narrow things down enough. Probably need composite indexes on (status, show_id) for bookings and (movie_id, screen_id) for shows.

**R11 (52 ms), R21 (52 ms), R24 (62 ms)** — all aggregate queries doing full table scans. R21 is interesting because it uses idx_bookings_customer_id but still scans everything since the filter (booked_at >= 2026-01-01) covers most of the data. R24 joins booking_seats with seats, screens, venues — no useful index for this join pattern.

**R17 (35 ms), R22 (28 ms), R25 (27 ms), R08 (28 ms)** — moderate but could be improved. R22 is the pagination query with OFFSET 100000 which is inherently slow (has to skip 100K rows). R17 uses a NOT EXISTS anti-join with a seq scan on booking_seats.

### Write queries

All writes are fast (< 11 ms). W02 is the slowest at ~10 ms since it involves finding the oldest PENDING booking and then checking for unsold seats with NOT EXISTS, but it's still acceptable for a transactional workload.

## Summary stats

- **Total baseline time (all 30 queries, avg):** ~866 ms
- **Fastest:** R23 (0.028 ms) — phone lookup, direct index scan
- **Slowest:** R10 (247.654 ms) — cleaning gap self-join
- **Queries > 50 ms:** R10, R15, R12, R18, R11, R21, R24 (7 queries)
- **Queries > 20 ms:** above + R17, R08, R22, R25, R16 (12 queries total)

The raw EXPLAIN ANALYZE plans for each query (all 3 runs) are saved in `benchmarks/results/baseline/`. The summary CSV is at `benchmarks/results/baseline/summary.csv`.

