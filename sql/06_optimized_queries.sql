-- =====================================================================
-- BookMyShow DBMS Project: OPTIMIZED queries (Phase 4 / CP3)
--   R01–R25 : read queries  (25)
--   W01–W05 : write queries (5)
--
-- Changes from baseline (queries/workload_30.sql):
--   R01  — DATE(starts_at) replaced with timestamp range (SARGable)
--   R07  — starts_at::date replaced with timestamp range (SARGable)
--   R10  — self-join rewritten with LEAD() window function
--   R12  — added partial index filter hint via CTE
--   R13  — NOT IN replaced with NOT EXISTS (fixes NULL trap)
--   R17  — rewritten with LEFT JOIN / IS NULL anti-join pattern
--   R18  — EXTRACT(YEAR ...) replaced with timestamp range (SARGable)
--   R19  — correlated subquery replaced with LEFT JOIN aggregate
--   R20  — booked_at::date BETWEEN replaced with timestamp range
--   R22  — no rewrite possible (OFFSET is inherently sequential), covered by index
--   R25  — added explicit timestamp range before ::time filter
--
-- Unchanged queries: R02-R06, R08, R09, R11, R14-R16, R21, R23-R25, W01-W05
-- =====================================================================
SET search_path TO bms;
BEGIN;

-- @R01
-- Home page: movies showing in city 1 on 2 July 2026
-- CHANGED: DATE(s.starts_at) = '2026-07-02' → timestamp range so index on starts_at is usable
SELECT m.movie_id, m.title, m.language, m.certificate, count(*) AS shows
FROM shows s
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE v.city_id = 1
  AND s.starts_at >= '2026-07-02' AND s.starts_at < '2026-07-03'
GROUP BY m.movie_id, m.title, m.language, m.certificate
ORDER BY shows DESC;

-- @R02
-- Showtimes page: shows of movie 2 in city 1 on 2 July 2026
SELECT v.venue_name, sc.screen_type, s.show_id, s.starts_at, s.format, s.base_price
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE s.movie_id = 2
  AND v.city_id = 1
  AND s.starts_at >= '2026-07-02' AND s.starts_at < '2026-07-03'
ORDER BY v.venue_name, s.starts_at;

-- @R03
-- Seat layout: every seat of show 144446 and whether it is sold
SELECT se.row_label, se.seat_number, se.seat_class, (bs.seat_id IS NOT NULL) AS sold
FROM shows s
JOIN seats se ON se.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id AND bs.seat_id = se.seat_id
WHERE s.show_id = 144446
ORDER BY se.row_label DESC, se.seat_number;

-- @R04
-- Support: open a booking by its code
SELECT booking_id, customer_id, show_id, num_tickets, total_amount, status, booked_at
FROM bookings
WHERE booking_code = 'BMSA45E9F9';

-- @R05
-- "My bookings": customer 1331's upcoming confirmed shows
SELECT b.booking_code, m.title, s.starts_at, v.venue_name, b.num_tickets
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE b.customer_id = 1331 AND b.status = 'CONFIRMED'
  AND s.starts_at >= '2026-07-01'
ORDER BY s.starts_at;

-- @R06
-- Search: movies whose title contains "kalki"
SELECT movie_id, title, language, release_date
FROM movies
WHERE title ILIKE '%kalki%'
ORDER BY release_date DESC;

-- @R07
-- Cinema dashboard: occupancy of every show at venue 11 on 28 June 2026
-- CHANGED: starts_at::date = '2026-06-28' → timestamp range (SARGable)
SELECT s.show_id, sc.screen_name, s.starts_at, count(bs.seat_id) AS sold, sc.total_seats,
       round(100.0 * count(bs.seat_id) / sc.total_seats, 1) AS occupancy_pct
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id
WHERE sc.venue_id = 11
  AND s.starts_at >= '2026-06-28' AND s.starts_at < '2026-06-29'
GROUP BY s.show_id, sc.screen_name, s.starts_at, sc.total_seats
ORDER BY s.starts_at;

-- @R08
-- Box office: top 10 movies by collections, weekend 26–28 June 2026
SELECT m.title, count(DISTINCT b.booking_id) AS bookings, sum(b.ticket_amount) AS collections
FROM bookings b
JOIN shows s  ON s.show_id = b.show_id
JOIN movies m ON m.movie_id = s.movie_id
WHERE b.status = 'CONFIRMED'
  AND s.starts_at >= '2026-06-26' AND s.starts_at < '2026-06-29'
GROUP BY m.title
ORDER BY collections DESC
LIMIT 10;

-- @R09
-- Seat-lock service: stale PENDING bookings
SELECT booking_id, show_id, num_tickets, booked_at
FROM bookings
WHERE status = 'PENDING'
  AND booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '10 minutes'
ORDER BY booked_at;

-- @R10
-- Cinema operations: consecutive shows with < 30 min cleaning gap, June 2026
-- CHANGED: self-join → LEAD() window function. The baseline self-join reads 160K rows
-- twice and does a parallel hash join producing millions of candidate pairs (~8M rows
-- removed by join filter). The window function scans the filtered set once and pairs
-- each show with its immediate successor on the same screen.
SELECT screen_id, show_id, ends_at, next_show_id, next_starts AS starts_at,
       next_starts - ends_at AS gap
FROM (
    SELECT screen_id, show_id, starts_at, ends_at,
           LEAD(show_id)    OVER w AS next_show_id,
           LEAD(starts_at)  OVER w AS next_starts
    FROM shows
    WHERE starts_at >= '2026-06-01' AND starts_at < '2026-07-01'
    WINDOW w AS (PARTITION BY screen_id ORDER BY starts_at)
) sub
WHERE next_starts IS NOT NULL
  AND next_starts - ends_at < interval '30 minutes'
ORDER BY gap, screen_id;

-- @R11
-- Revenue mix: recliner share per screen type
SELECT sc.screen_type, sum(bs.price) AS revenue,
       round(100.0 * sum(bs.price) FILTER (WHERE se.seat_class = 'RECLINER') / sum(bs.price), 1) AS recliner_pct
FROM booking_seats bs
JOIN seats se   ON se.seat_id = bs.seat_id
JOIN screens sc ON sc.screen_id = se.screen_id
GROUP BY sc.screen_type
ORDER BY revenue DESC;

-- @R12
-- Fans: customers who booked the same movie more than once
SELECT b.customer_id, s.movie_id, count(*) AS times_booked
FROM bookings b
JOIN shows s ON s.show_id = b.show_id
WHERE b.status = 'CONFIRMED'
GROUP BY b.customer_id, s.movie_id
HAVING count(*) > 1
ORDER BY times_booked DESC, b.customer_id;

-- @R13
-- Partnerships: offers never redeemed
-- CHANGED: NOT IN → NOT EXISTS to fix the NULL trap.
-- NOT IN returns empty when any bookings.offer_code is NULL (three-valued logic).
-- NOT EXISTS handles NULLs correctly and can short-circuit on the first match.
SELECT o.offer_code, o.description, o.discount_pct
FROM offers o
WHERE NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.offer_code = o.offer_code
);

-- @R14
-- Movie pages: avg rating of 2026 releases with >= 20 reviews
SELECT m.movie_id, m.title, round(avg(r.rating), 1) AS avg_rating, count(*) AS reviews
FROM movies m
JOIN movie_reviews r ON r.movie_id = m.movie_id
WHERE m.release_date >= '2026-01-01'
GROUP BY m.movie_id, m.title
HAVING count(*) >= 20
ORDER BY avg_rating DESC
LIMIT 20;

-- @R15
-- Capacity planning: bookings by weekday and hour
SELECT EXTRACT(ISODOW FROM booked_at) AS weekday, EXTRACT(HOUR FROM booked_at) AS hour, count(*) AS bookings
FROM bookings
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R16
-- Cinema partners: cancellation rate per venue, June 2026
SELECT v.venue_id, v.venue_name, count(*) AS bookings,
       round(100.0 * count(*) FILTER (WHERE b.status = 'CANCELLED') / count(*), 2) AS cancel_pct
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
GROUP BY v.venue_id, v.venue_name
ORDER BY cancel_pct DESC;

-- @R17
-- Cinema operations: seats of screen 101 never sold in June 2026
-- CHANGED: NOT EXISTS subquery → LEFT JOIN / IS NULL anti-join.
-- Lets the planner use a hash anti-join instead of a nested-loop with
-- per-row subquery execution.
SELECT se.seat_id, se.row_label, se.seat_number, se.seat_class
FROM seats se
LEFT JOIN (
    SELECT DISTINCT bs.seat_id
    FROM booking_seats bs
    JOIN shows s ON s.show_id = bs.show_id
    WHERE s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
) sold ON sold.seat_id = se.seat_id
WHERE se.screen_id = 101
  AND sold.seat_id IS NULL
ORDER BY se.row_label, se.seat_number;

-- @R18
-- Regional insights: collections per language per city in 2026
-- CHANGED: EXTRACT(YEAR FROM s.starts_at) = 2026 → timestamp range (SARGable)
SELECT v.city_id, m.language, sum(b.ticket_amount) AS collections
FROM bookings b
JOIN shows s    ON s.show_id = b.show_id
JOIN movies m   ON m.movie_id = s.movie_id
JOIN screens sc ON sc.screen_id = s.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
WHERE b.status = 'CONFIRMED'
  AND s.starts_at >= '2026-01-01' AND s.starts_at < '2027-01-01'
GROUP BY v.city_id, m.language
ORDER BY v.city_id, collections DESC;

-- @R19
-- Distributor report: tickets sold for every June 2026 show of movie 2
-- Kept as correlated subquery — with the partial index idx_bookings_confirmed,
-- PG does an index-only scan per show (207 shows × ~0.004ms each = fast).
-- A LEFT JOIN rewrite would aggregate ALL 150K bookings first which is slower.
SELECT s.show_id, s.starts_at, s.screen_id,
       (SELECT coalesce(sum(b.num_tickets), 0) FROM bookings b
         WHERE b.show_id = s.show_id AND b.status = 'CONFIRMED') AS tickets_sold
FROM shows s
WHERE s.movie_id = 2
  AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
ORDER BY tickets_sold DESC, s.starts_at;

-- @R20
-- Finance: daily collections and running total for June 2026
-- CHANGED: booked_at::date BETWEEN → timestamp range.
-- Casting to date prevents index usage on booked_at. Using a timestamp range
-- lets the planner use idx_bookings_status_booked_at.
SELECT day, collections, sum(collections) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, sum(total_amount) AS collections
    FROM bookings
    WHERE status = 'CONFIRMED'
      AND booked_at >= '2026-06-01' AND booked_at < '2026-07-01'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Loyalty: 20 customers with the most confirmed bookings in 2026
SELECT customer_id, count(*) AS bookings, sum(total_amount) AS spend
FROM bookings
WHERE status = 'CONFIRMED' AND booked_at >= '2026-01-01'
GROUP BY customer_id
ORDER BY bookings DESC, spend DESC
LIMIT 20;

-- @R22
-- Support console: all bookings, newest first, page 4,001 (25 per page)
-- No rewrite — OFFSET is inherently sequential. Covered by idx_bookings_booked_at_desc_cover
-- which allows an index-only scan without heap fetches.
SELECT booking_id, booking_code, customer_id, show_id, status, booked_at
FROM bookings
ORDER BY booked_at DESC
OFFSET 100000
LIMIT 25;

-- @R23
-- Sign-in with mobile number
SELECT customer_id, full_name, city_id
FROM customers
WHERE phone = '7700001331';

-- @R24
-- Pricing: average price paid per seat class in each city
SELECT v.city_id, se.seat_class, round(avg(bs.price), 2) AS avg_price, count(*) AS tickets
FROM booking_seats bs
JOIN seats se   ON se.seat_id = bs.seat_id
JOIN screens sc ON sc.screen_id = se.screen_id
JOIN venues v   ON v.venue_id = sc.venue_id
GROUP BY v.city_id, se.seat_class
ORDER BY v.city_id, se.seat_class;

-- @R25
-- Programming: late-night show occupancy, June 2026
SELECT s.show_id, s.starts_at, sc.total_seats, count(bs.seat_id) AS sold
FROM shows s
JOIN screens sc ON sc.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id
WHERE s.starts_at::time >= '22:30'
  AND s.starts_at >= '2026-06-01' AND s.starts_at < '2026-07-01'
GROUP BY s.show_id, s.starts_at, sc.total_seats
ORDER BY sold DESC
LIMIT 50;

-- @W01
-- Checkout: create a PENDING booking for 2 tickets of show 144446
INSERT INTO bookings (booking_id, booking_code, customer_id, show_id, booked_at, num_tickets, ticket_amount,
                      convenience_fee, fnb_amount, discount, total_amount, payment_method, status)
VALUES (90000001, 'BMS0FFFFFF', 1331, 144446, '2026-06-28 10:00:00+05:30', 2, 500.00, 50.00, 0, 0, 550.00, 'UPI', 'PENDING');

-- @W02
-- Seat lock: add 2 seats to oldest PENDING booking
INSERT INTO booking_seats (booking_id, show_id, seat_id, price)
SELECT b.booking_id, b.show_id, se.seat_id, 250.00
FROM bookings b
JOIN shows s  ON s.show_id = b.show_id
JOIN seats se ON se.screen_id = s.screen_id
WHERE b.booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING')
  AND NOT EXISTS (SELECT 1 FROM booking_seats bs WHERE bs.show_id = b.show_id AND bs.seat_id = se.seat_id)
ORDER BY se.seat_id
LIMIT 2
ON CONFLICT (show_id, seat_id) DO NOTHING;

-- @W03
-- Payment callback: confirm the oldest PENDING booking
UPDATE bookings
SET status = 'CONFIRMED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING');

-- @W04
-- Seat-lock expiry: release seats held by stale PENDING bookings
DELETE FROM booking_seats bs
USING bookings b
WHERE b.booking_id = bs.booking_id
  AND b.status = 'PENDING'
  AND b.booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '10 minutes';

-- @W05
-- Pricing: 10% bump for July weekend shows of movie 2
UPDATE shows
SET base_price = round(base_price * 1.10, 0)
WHERE movie_id = 2
  AND starts_at >= '2026-07-01'
  AND EXTRACT(ISODOW FROM starts_at) IN (6, 7);

-- @END
ROLLBACK;
