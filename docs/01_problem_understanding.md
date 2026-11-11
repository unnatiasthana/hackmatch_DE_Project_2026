# CP1 — Problem Understanding
## BookMyShow Online Ticketing System — DBMS Project

**Team:** BookMyShow DBMS Project Group  
**Date:** November 2026  
**Phase:** CP1 — Problem Understanding & Schema Design

---

## 1. Overview

BookMyShow is India's largest online ticketing platform. Users can browse movies and events, choose screens and showtimes, pick seats, apply discount offers, pay, and receive a booking confirmation. The system needs to store and query a large volume of transactional and analytical data efficiently. This document breaks down the eight core problem statements (P1–P8), identifies stakeholders, classifies the query type, and lists assumptions made during design.

---

## 2. Problem Statements

| # | Business Need | Stakeholder(s) | Classification | Key Tables Involved |
|---|---------------|----------------|----------------|---------------------|
| **P1** | A customer searches for shows currently running in their city — filtered by movie title, language, format (2D/3D/IMAX), date range, and multiplex chain. Results must be near-instant. | End customer browsing on app/web | **Customer-facing / Real-time** | `cities`, `venues`, `screens`, `shows`, `movies` |
| **P2** | At the time of seat selection, the system must display which seats are still available (not already booked or held) for a given show, and prevent two users from booking the same seat simultaneously. | End customer selecting seats; system concurrency control | **Customer-facing / Real-time** | `booking_seats`, `shows`, `seats`, `screens` |
| **P3** | A customer applies a promo/offer code at checkout. The system must validate the code (not expired, within usage window), compute the discount, and cap it at `max_discount`. The final `total_amount` is recorded with the discount applied. | End customer at payment step; finance/billing | **Customer-facing / Real-time** | `offers`, `bookings` |
| **P4** | After payment, the system confirms the booking, assigns a unique `booking_code` (pattern `BMS` + 7 uppercase hex chars), persists seat assignments in `booking_seats`, and sends confirmation. Cancellations should release seats by deleting `booking_seats` rows. | End customer; payment gateway; support team | **Customer-facing / Real-time** | `bookings`, `booking_seats`, `customers`, `shows` |
| **P5** | Operations/revenue team needs daily/weekly revenue reports: total revenue per venue, per city, per multiplex chain, and per movie — broken down by format, seat class, and payment method. | Multiplex operators; finance team; management | **Reporting / Analytics** | `bookings`, `booking_seats`, `shows`, `movies`, `screens`, `venues`, `cities` |
| **P6** | The marketing team wants to know which offers drive the most revenue, how many bookings used each offer, average discount given, and which customer segments use them most. They also need to identify offers that have never been redeemed. | Marketing team; product managers | **Reporting / Analytics** | `offers`, `bookings`, `customers` |
| **P7** | Movie performance dashboard: average audience rating per movie (`movie_reviews`), number of reviews, occupancy rate (tickets sold / total seats across all shows), and comparison across languages and genres. | Content/acquisition team; movie studios | **Reporting / Analytics** | `movie_reviews`, `movies`, `bookings`, `shows`, `screens` |
| **P8** | Identify loyal/high-value customers: total amount spent, number of bookings, favourite genre/language, preferred multiplex, and flag customers whose total spend exceeds a threshold (for loyalty rewards). | CRM / loyalty team; marketing | **Reporting / Analytics** | `customers`, `bookings`, `booking_seats`, `shows`, `movies`, `venues` |

---

## 3. Detailed Problem Descriptions

### P1 — Show Discovery & Search

**Business need:** When a user opens BookMyShow and selects their city, they should immediately see movies playing near them with available showtimes. Filters like language (Hindi, English, Tamil…), format (2D, IMAX, 4DX), date, and multiplex chain (PVR, INOX, Cinepolis…) must refine the list quickly.  
This is the highest-traffic query in the system — every user session begins here.

**Assumptions:**
- A "currently running" show is one where `shows.starts_at` is in the future (or within the last 15 minutes).
- Venue is mapped to a city via `venues.city_id`; customers have a home city (`customers.city_id`) used as default.
- Chain information is stored in `venues.chain` as a denormalized string (not a separate lookup table) for simplicity.

---

### P2 — Seat Availability & Double-Booking Prevention

**Business need:** The seat map must reflect real-time availability. When a seat is booked (a row exists in `booking_seats`), it must not be selectable by another user. If two users simultaneously try to book the same seat for the same show, only one should succeed.

**Assumptions:**
- Availability = seat NOT present in `booking_seats` for that `show_id` (whether the linked booking is PENDING or CONFIRMED). CANCELLED bookings have their `booking_seats` rows deleted.
- Double-booking is prevented by the `PRIMARY KEY (show_id, seat_id)` on `booking_seats` — a concurrent INSERT of the same `(show_id, seat_id)` will raise a unique-violation error at the DB level.
- There is no separate "seat hold / reservation TTL" table in this phase; PENDING bookings hold seats indefinitely until cancelled.

---

### P3 — Offer / Promo Code Validation

**Business need:** At checkout, a customer may enter an offer code. The system validates: (a) code exists, (b) current date is within `valid_from`–`valid_to`, (c) discount = `ticket_amount × discount_pct / 100`, capped at `max_discount`. The final amounts are stored in `bookings`.

**Assumptions:**
- An offer code is optional; `bookings.offer_code` is nullable.
- No per-customer usage limit is modelled in this phase (only date-based validity).
- `discount` column stores the actual discount applied (after cap), not `discount_pct`.
- `total_amount = ticket_amount + convenience_fee + fnb_amount − discount`.

---

### P4 — Booking Confirmation & Cancellation

**Business need:** On successful payment, booking status changes from `PENDING` → `CONFIRMED`. A unique `booking_code` (e.g., `BMS0004F28`) is generated. On cancellation, status → `CANCELLED` and all rows in `booking_seats` for that booking are deleted (seats freed).

**Assumptions:**
- `booking_code` is generated by the application layer and stored; the CHECK constraint validates format.
- Deleting `booking_seats` on cancellation is handled by `ON DELETE CASCADE` from `bookings` to `booking_seats`.
- Partial cancellations (cancelling individual seats) are out of scope.

---

### P5 — Revenue Reporting

**Business need:** Operations needs aggregated revenue: per venue, per city, per chain, per movie, per format, per seat class, per payment method — with daily/weekly/monthly granularity.

**Assumptions:**
- Only `CONFIRMED` bookings contribute to revenue reports.
- `total_amount` in `bookings` is the authoritative revenue figure.
- `fnb_amount` and `convenience_fee` are tracked as separate columns for gross-margin analysis.

---

### P6 — Offer Analytics & Redemption Rates

**Business need:** Which offers are used most? What's the average discount given? Which offers have zero redemptions? The classic trap: `NOT IN (SELECT offer_code FROM bookings)` returns empty when any `offer_code` IS NULL — the correct query uses `NOT EXISTS` or filters NULLs.

**Assumptions:**
- An offer "has been used" if at least one CONFIRMED booking references it.
- The NULL trap in R13 is flagged as a known data-quality problem (see §7 of the schema doc).

---

### P7 — Movie Performance Dashboard

**Business need:** Rate movies by audience score (avg of `movie_reviews.rating`), review count, and occupancy (tickets sold ÷ total seat capacity across all shows).

**Assumptions:**
- Rating is an integer 1–10; average is computed at query time.
- `review_text` is nullable (a customer may leave a star-only rating).
- Occupancy = `SUM(b.num_tickets for CONFIRMED) / SUM(s.total_seats for all shows of that movie)`.

---

### P8 — Customer Loyalty Analytics

**Business need:** Rank customers by total spend, identify preferred cinema chains, and segment by genre/language affinity for targeted marketing.

**Assumptions:**
- "Total spend" = `SUM(total_amount)` over CONFIRMED bookings.
- Loyalty threshold (e.g., \$5000 / ₹50,000) is a parameter set at query time.
- Genre is not a separate column in this dataset; language is used as a proxy for content segmentation.

---

## 4. Assumptions Summary

| # | Assumption |
|---|-----------|
| A1 | The application layer enforces session-level concurrency (optimistic locking or SELECT FOR UPDATE) for seat selection; the DB enforces the hard constraint via PK on `booking_seats`. |
| A2 | Cancelled bookings retain their `bookings` row (for audit) but all `booking_seats` rows are deleted (CASCADE). |
| A3 | Offer codes are date-validated only; per-user or per-code redemption limits are out of scope. |
| A4 | `screens.total_seats` is a denormalized count kept for query performance; it must be maintained consistent with the number of rows in `seats` for that screen. |
| A5 | `shows.ends_at` is derivable from `starts_at + movies.duration_min` but stored for quick overlap-detection queries. |
| A6 | A customer can review a movie at most once per booking but we do not enforce a composite unique on `(movie_id, customer_id)` — we allow a customer to submit reviews after multiple viewings of the same movie. |
| A7 | All monetary values are in INR (Indian Rupees); `NUMERIC(10,2)` supports up to ₹99,999,999.99. |
| A8 | The `chain` column in `venues` is a free-text string matching known chain brands (PVR, INOX, Cinepolis, Miraj, Carnival…); no separate lookup table is used to avoid over-normalization. |
