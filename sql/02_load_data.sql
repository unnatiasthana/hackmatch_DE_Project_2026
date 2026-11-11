-- =============================================================================
-- BookMyShow Ticketing System — Data Load Script
-- File:    sql/02_load_data.sql
-- Phase:   CP1
-- DB:      PostgreSQL 15
-- =============================================================================
-- Usage:
--   psql -U <user> -d <database> -f sql/02_load_data.sql
--
-- The \copy commands below use relative paths from the repo root.
-- Run psql from the repository root directory so that seed_data/ resolves correctly.
--
-- Load order respects FK dependencies:
--   cities → venues → screens → seats
--   movies
--   cities → customers
--   shows (needs movies + screens)
--   offers
--   bookings (needs customers + shows + offers)
--   booking_seats (needs bookings + shows + seats)
--   movie_reviews (needs movies + customers)
-- =============================================================================

SET search_path TO bms;

-- -----------------------------------------------------------------------------
-- Step 1: Load reference / master data
-- -----------------------------------------------------------------------------

\copy cities  FROM 'seed_data/cities.csv'  WITH (FORMAT csv, HEADER true)
\copy venues  FROM 'seed_data/venues.csv'  WITH (FORMAT csv, HEADER true)
\copy screens FROM 'seed_data/screens.csv' WITH (FORMAT csv, HEADER true)
\copy seats   FROM 'seed_data/seats.csv'   WITH (FORMAT csv, HEADER true)
\copy movies  FROM 'seed_data/movies.csv'  WITH (FORMAT csv, HEADER true)

-- -----------------------------------------------------------------------------
-- Step 2: Load customer data
-- -----------------------------------------------------------------------------

\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)

-- -----------------------------------------------------------------------------
-- Step 3: Load transactional master data
-- -----------------------------------------------------------------------------

\copy shows  FROM 'seed_data/shows.csv'  WITH (FORMAT csv, HEADER true)
\copy offers FROM 'seed_data/offers.csv' WITH (FORMAT csv, HEADER true)

-- -----------------------------------------------------------------------------
-- Step 4: Load bookings and seat assignments
-- -----------------------------------------------------------------------------

\copy bookings      FROM 'seed_data/bookings.csv'      WITH (FORMAT csv, HEADER true)
\copy booking_seats FROM 'seed_data/booking_seats.csv' WITH (FORMAT csv, HEADER true)

-- -----------------------------------------------------------------------------
-- Step 5: Load reviews
-- -----------------------------------------------------------------------------

\copy movie_reviews FROM 'seed_data/movie_reviews.csv' WITH (FORMAT csv, HEADER true)

-- -----------------------------------------------------------------------------
-- Step 6: Update statistics for the query planner
-- -----------------------------------------------------------------------------

ANALYZE;

-- =============================================================================
-- ROW COUNT VERIFICATION
-- Expected: non-zero counts for all tables after a successful load.
-- =============================================================================

SELECT 'cities'        AS tbl, COUNT(*) AS row_count FROM cities
UNION ALL
SELECT 'venues',               COUNT(*)               FROM venues
UNION ALL
SELECT 'screens',              COUNT(*)               FROM screens
UNION ALL
SELECT 'seats',                COUNT(*)               FROM seats
UNION ALL
SELECT 'movies',               COUNT(*)               FROM movies
UNION ALL
SELECT 'shows',                COUNT(*)               FROM shows
UNION ALL
SELECT 'customers',            COUNT(*)               FROM customers
UNION ALL
SELECT 'offers',               COUNT(*)               FROM offers
UNION ALL
SELECT 'bookings',             COUNT(*)               FROM bookings
UNION ALL
SELECT 'booking_seats',        COUNT(*)               FROM booking_seats
UNION ALL
SELECT 'movie_reviews',        COUNT(*)               FROM movie_reviews
ORDER BY tbl;

-- =============================================================================
-- INTEGRITY CHECK 1
-- Every booked seat must belong to the same screen as the show it was booked for.
-- A non-zero count indicates corrupted seed data or an application bug.
-- Expected result: 0
-- =============================================================================

SELECT COUNT(*) AS violations_check1_seat_screen_mismatch
FROM booking_seats bs
JOIN bookings b  ON b.booking_id = bs.booking_id
JOIN shows    s  ON s.show_id    = b.show_id
JOIN seats    se ON se.seat_id   = bs.seat_id
WHERE se.screen_id <> s.screen_id;

-- =============================================================================
-- INTEGRITY CHECK 2
-- For CONFIRMED and PENDING bookings, num_tickets must equal the actual number
-- of rows in booking_seats.  Cancelled bookings are excluded because their
-- booking_seats rows are deleted (CASCADE) upon cancellation.
-- Expected result: 0
-- =============================================================================

SELECT COUNT(*) AS mismatches_check2_num_tickets_vs_seat_count
FROM bookings b
LEFT JOIN (
    SELECT booking_id, COUNT(*) AS seat_count
    FROM   booking_seats
    GROUP  BY booking_id
) bs ON bs.booking_id = b.booking_id
WHERE b.status IN ('CONFIRMED', 'PENDING')
  AND b.num_tickets <> COALESCE(bs.seat_count, 0);

-- =============================================================================
-- INTEGRITY CHECK 3
-- No show should reference a movie or screen that does not exist.
-- FK constraints prevent this in a correct load, but this check verifies
-- that the data files themselves are internally consistent before FK errors
-- abort the load.
-- Expected result: 0
-- =============================================================================

SELECT COUNT(*) AS orphan_shows_check3
FROM shows s
WHERE NOT EXISTS (SELECT 1 FROM movies  m  WHERE m.movie_id  = s.movie_id)
   OR NOT EXISTS (SELECT 1 FROM screens sc WHERE sc.screen_id = s.screen_id);

-- =============================================================================
-- BONUS SANITY CHECKS
-- =============================================================================

-- Check 4: booking_code format compliance
-- All booking codes must match the pattern BMS followed by 7 uppercase hex chars.
SELECT COUNT(*) AS invalid_booking_codes_check4
FROM bookings
WHERE booking_code !~ '^BMS[0-9A-F]{7}$';

-- Check 5: Offer date validity — valid_to should not be before valid_from
SELECT offer_code, valid_from, valid_to
FROM offers
WHERE valid_to < valid_from;

-- Check 6: Shows that end before or at the same time they start
SELECT show_id, starts_at, ends_at
FROM shows
WHERE ends_at <= starts_at;

-- Check 7: Cancelled bookings should have no rows in booking_seats
SELECT COUNT(*) AS cancelled_with_seats_check7
FROM bookings b
WHERE b.status = 'CANCELLED'
  AND EXISTS (SELECT 1 FROM booking_seats bs WHERE bs.booking_id = b.booking_id);

-- Check 8: Ratings must be in range 1-10 (belt-and-suspenders; also enforced by CHECK)
SELECT COUNT(*) AS out_of_range_ratings_check8
FROM movie_reviews
WHERE rating < 1 OR rating > 10;
