-- =============================================================================
-- BookMyShow Ticketing System — Optimization Indexes
-- File:    sql/05_indexes.sql
-- Phase:   CP3
-- DB:      PostgreSQL 15
--
-- Run AFTER 01_schema.sql and 02_load_data.sql.
-- These indexes target the slowest queries from the baseline benchmark.
-- =============================================================================

SET search_path TO bms;

-- -----------------------------------------------------------------------------
-- 1. shows: composite (screen_id, starts_at) covering index
--    Targets: R10 (cleaning gap self-join — the slowest query at 248ms),
--             R01 (now-showing), R07 (venue occupancy), R16 (cancel rate)
--    Rationale: R10 joins shows with itself on screen_id and filters by starts_at.
--    The baseline does a parallel hash join scanning all 160K rows twice.
--    This composite index lets PG do an index scan per screen for the date range,
--    and INCLUDE covers the columns needed without going to the heap.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_shows_screen_starts
    ON shows (screen_id, starts_at)
    INCLUDE (show_id, movie_id, ends_at, format, base_price);

-- -----------------------------------------------------------------------------
-- 2. bookings: partial index for CONFIRMED bookings (the most common filter)
--    Targets: R08 (box office, 28ms), R12 (fans, 74ms), R18 (regional, 74ms),
--             R21 (loyalty, 52ms), R20 (daily collections, 16ms)
--    Rationale: Most analytics queries filter WHERE status = 'CONFIRMED'.
--    ~85% of bookings are confirmed, but a partial index still helps because
--    it's narrower and the planner can skip the status check in the filter.
--    INCLUDE covers the columns most analytics queries SELECT.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_bookings_confirmed
    ON bookings (show_id, customer_id, ticket_amount, num_tickets, total_amount)
    WHERE status = 'CONFIRMED';

-- -----------------------------------------------------------------------------
-- 3. bookings: composite for status + booked_at queries
--    Targets: R20 (daily collections, 16ms), R21 (loyalty, 52ms),
--             R15 (booking heatmap, 105ms)
--    Rationale: R20 filters on status = 'CONFIRMED' and booked_at date range.
--    R21 filters on status and booked_at >= '2026-01-01'.
--    The baseline uses separate single-column indexes; a composite helps the
--    planner narrow rows early.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_bookings_status_booked_at
    ON bookings (status, booked_at);

-- -----------------------------------------------------------------------------
-- 4. booking_seats: index on seat_id for join performance
--    Targets: R11 (revenue mix, 52ms), R17 (never-sold seats, 35ms),
--             R24 (avg price per seat class, 62ms), R25 (late-night occupancy, 27ms)
--    Rationale: The PK is (show_id, seat_id), so lookups by seat_id alone
--    require a full index scan. Many queries join booking_seats to seats on
--    seat_id, and the baseline does seq scans on the 300K-row table.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_booking_seats_seat_id
    ON booking_seats (seat_id)
    INCLUDE (price, show_id, booking_id);

-- -----------------------------------------------------------------------------
-- 5. bookings: covering index for the pagination query (R22, 28ms)
--    Rationale: R22 does ORDER BY booked_at DESC OFFSET 100000 LIMIT 25.
--    With a covering index the planner can do an index-only scan and skip
--    100K entries without touching the heap for most of them.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_bookings_booked_at_desc_cover
    ON bookings (booked_at DESC)
    INCLUDE (booking_id, booking_code, customer_id, show_id, status);

-- -----------------------------------------------------------------------------
-- 6. bookings: composite for customer + status (My Bookings, Loyalty)
--    Targets: R05 (my bookings), R12 (fans), R21 (loyalty)
-- -----------------------------------------------------------------------------
CREATE INDEX idx_bookings_customer_status
    ON bookings (customer_id, status);

-- -----------------------------------------------------------------------------
-- 7. shows: composite (movie_id, starts_at) covering
--    Targets: R08 (box office), R19 (distributor report)
--    Already have single-column indexes on each; composite is better for
--    queries that filter on both movie_id and date range.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_shows_movie_starts
    ON shows (movie_id, starts_at)
    INCLUDE (show_id, screen_id, base_price);

-- -----------------------------------------------------------------------------
-- 8. seats: composite for screen lookups with class info
--    Targets: R11 (revenue by seat class), R24 (avg price per class per city)
-- -----------------------------------------------------------------------------
CREATE INDEX idx_seats_screen_class
    ON seats (screen_id, seat_class)
    INCLUDE (seat_id, row_label, seat_number);

-- -----------------------------------------------------------------------------
-- After creating all indexes, update table statistics so the planner
-- knows about the new access paths.
-- -----------------------------------------------------------------------------
ANALYZE;
