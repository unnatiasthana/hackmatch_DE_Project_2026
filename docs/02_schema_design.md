# CP1 — Schema Design
## BookMyShow Online Ticketing System — DBMS Project

**Team:** BookMyShow DBMS Project Group  
**Date:** November 2026  
**Phase:** CP1 — Problem Understanding & Schema Design

---

## 1. ER Diagram

The entity-relationship diagram is provided in `diagrams/er_diagram.md` (render it with a Mermaid-compatible viewer or export to PNG).  
Key entity sets: **cities, venues, screens, seats, movies, shows, customers, offers, bookings, booking_seats, movie_reviews** (11 tables total).

---

## 2. Data Dictionary

### 2.1 `cities`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `city_id` | `SERIAL` | PK | Auto-increment surrogate key |
| `city_name` | `VARCHAR(100)` | NOT NULL | City display name (e.g., "Mumbai") |
| `state` | `VARCHAR(100)` | NOT NULL | State name for regional grouping |

**FDs:** `city_id → city_name, state`  
**Normal Form:** BCNF — only one candidate key (`city_id`); all non-key attributes depend solely on it. No partial or transitive dependencies.

---

### 2.2 `venues`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `venue_id` | `SERIAL` | PK | Surrogate key |
| `venue_name` | `VARCHAR(200)` | NOT NULL | Full multiplex name |
| `city_id` | `INT` | NOT NULL, FK → cities | Venue's city |
| `chain` | `VARCHAR(100)` | NOT NULL | Multiplex chain brand (PVR, INOX, …) |
| `address` | `TEXT` | NOT NULL | Street address |

**FDs:** `venue_id → venue_name, city_id, chain, address`  
**Normal Form:** BCNF — `venue_id` is the only determinant. `chain` is intentionally denormalized (see §5.2).

---

### 2.3 `screens`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `screen_id` | `SERIAL` | PK | Surrogate key |
| `venue_id` | `INT` | NOT NULL, FK → venues | Screen belongs to this venue |
| `screen_name` | `VARCHAR(100)` | NOT NULL | E.g., "Audi 1", "IMAX Hall" |
| `screen_type` | `VARCHAR(20)` | NOT NULL, CHECK enum | Technology type |
| `total_seats` | `SMALLINT` | NOT NULL, CHECK > 0 | Denormalized seat count (see §5.1) |

**FDs:** `screen_id → venue_id, screen_name, screen_type, total_seats`  
**Normal Form:** BCNF — sole determinant is `screen_id`.  
`total_seats` is a known denormalization; see §5.1.

---

### 2.4 `seats`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `seat_id` | `SERIAL` | PK | Surrogate key |
| `screen_id` | `INT` | NOT NULL, FK → screens | Seat belongs to this screen |
| `row_label` | `CHAR(1)` | NOT NULL | Row identifier A–Z |
| `seat_number` | `SMALLINT` | NOT NULL | Column number within row |
| `seat_class` | `VARCHAR(20)` | NOT NULL, CHECK enum | CLASSIC / PRIME / RECLINER |

**FDs:** `seat_id → screen_id, row_label, seat_number, seat_class`  
Candidate key: also `(screen_id, row_label, seat_number)` — physical address of a seat.  
**Normal Form:** BCNF — `seat_id` and the composite candidate key are equivalent determinants; every attribute depends on the whole key.

---

### 2.5 `movies`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `movie_id` | `SERIAL` | PK | Surrogate key |
| `title` | `VARCHAR(300)` | NOT NULL | Movie title |
| `language` | `VARCHAR(50)` | NOT NULL | Language of the print |
| `certificate` | `CHAR(2)` | NOT NULL, CHECK enum | Censor board rating U/UA/A/S |
| `duration_min` | `SMALLINT` | NOT NULL | Runtime in minutes |
| `release_date` | `DATE` | NOT NULL | Theatrical release date |

**FDs:** `movie_id → title, language, certificate, duration_min, release_date`  
**Normal Form:** BCNF — single surrogate key determines all attributes.

---

### 2.6 `shows`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `show_id` | `SERIAL` | PK | Surrogate key |
| `movie_id` | `INT` | NOT NULL, FK → movies | Movie being screened |
| `screen_id` | `INT` | NOT NULL, FK → screens | Screen where show is held |
| `starts_at` | `TIMESTAMPTZ` | NOT NULL | Show start time |
| `ends_at` | `TIMESTAMPTZ` | NOT NULL, CHECK > starts_at | Show end time (derived but stored) |
| `format` | `VARCHAR(10)` | NOT NULL, CHECK enum | 2D / 3D / IMAX / 4DX / DOLBY / SCREENX |
| `base_price` | `NUMERIC(10,2)` | NOT NULL, CHECK ≥ 0 | Base ticket price before class multiplier |

**FDs:** `show_id → movie_id, screen_id, starts_at, ends_at, format, base_price`  
Note: `ends_at` is functionally determined by `{movie_id, starts_at}` (via `duration_min`), but stored for performance.  
**Normal Form:** 3NF — `ends_at` has a transitive dependency through `movie_id → duration_min → ends_at`, but we accept this denormalization (see §5.1). Excluding `ends_at`, the table is BCNF.  
An exclusion constraint (using `btree_gist`) prevents two shows on the same screen overlapping in time.

---

### 2.7 `customers`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `customer_id` | `SERIAL` | PK | Surrogate key |
| `full_name` | `VARCHAR(200)` | NOT NULL | Display name |
| `email` | `VARCHAR(255)` | NOT NULL, UNIQUE | Login identifier |
| `phone` | `VARCHAR(15)` | NOT NULL, UNIQUE | Contact and OTP verification |
| `city_id` | `INT` | NOT NULL, FK → cities | Home city for default show search |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | Account creation timestamp |

**FDs:** `customer_id → full_name, email, phone, city_id, created_at`  
Candidate keys: `customer_id`, `email`, `phone`.  
**Normal Form:** BCNF — multiple candidate keys, all non-key attributes depend on each one.

---

### 2.8 `offers`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `offer_code` | `VARCHAR(20)` | PK | Natural key (e.g., "BLOCKBUSTER25") |
| `description` | `TEXT` | NOT NULL | Human-readable offer description |
| `discount_pct` | `NUMERIC(5,2)` | NOT NULL, CHECK 0–100 | Percentage discount |
| `max_discount` | `NUMERIC(10,2)` | NOT NULL | Cap on discount in INR |
| `valid_from` | `DATE` | NOT NULL | Offer start date |
| `valid_to` | `DATE` | NOT NULL | Offer expiry date |

**FDs:** `offer_code → description, discount_pct, max_discount, valid_from, valid_to`  
**Normal Form:** BCNF — single candidate key (natural PK).

---

### 2.9 `bookings`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `booking_id` | `SERIAL` | PK | Surrogate key |
| `booking_code` | `VARCHAR(10)` | NOT NULL, UNIQUE, CHECK regex | Display-safe reference code |
| `customer_id` | `INT` | NOT NULL, FK → customers | Who made the booking |
| `show_id` | `INT` | NOT NULL, FK → shows | Which show was booked |
| `booked_at` | `TIMESTAMPTZ` | NOT NULL | When booking was initiated |
| `num_tickets` | `SMALLINT` | NOT NULL, CHECK > 0 | Number of seats booked |
| `ticket_amount` | `NUMERIC(10,2)` | NOT NULL | Sum of seat prices (denormalized) |
| `convenience_fee` | `NUMERIC(10,2)` | NOT NULL | Platform service charge |
| `fnb_amount` | `NUMERIC(10,2)` | NOT NULL | Food & beverage pre-order total |
| `offer_code` | `VARCHAR(20)` | NULLABLE, FK → offers | Applied promo (NULL if none) |
| `discount` | `NUMERIC(10,2)` | NOT NULL, CHECK ≥ 0 | Actual discount applied |
| `total_amount` | `NUMERIC(10,2)` | NOT NULL, CHECK ≥ 0 | Final amount paid |
| `payment_method` | `VARCHAR(20)` | NOT NULL, CHECK enum | UPI / CREDIT_CARD / … |
| `status` | `VARCHAR(20)` | NOT NULL, CHECK enum | PENDING / CONFIRMED / CANCELLED |

**FDs:** `booking_id → all other attributes`  
`ticket_amount` is derivable from `SUM(booking_seats.price)` — kept for query performance (see §5.1).  
**Normal Form:** BCNF (excluding the known derivable columns). `booking_code` is an alternate candidate key.

---

### 2.10 `booking_seats`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `booking_id` | `INT` | NOT NULL, FK → bookings (CASCADE) | Parent booking |
| `show_id` | `INT` | NOT NULL, FK → shows (RESTRICT) | Redundant but enables the PK uniqueness check and join performance |
| `seat_id` | `INT` | NOT NULL, FK → seats (RESTRICT) | Which physical seat |
| `price` | `NUMERIC(10,2)` | NOT NULL, CHECK > 0 | Price paid for this specific seat |

**PK:** `(show_id, seat_id)` — this is the double-booking guard: a given seat in a given show can appear only once.  
**FDs:** `(show_id, seat_id) → booking_id, price`  
`show_id` is redundant (derivable via `bookings.show_id`) but essential for the PK to function without a full join.  
**Normal Form:** BCNF — the composite PK determines all attributes. `booking_id` → `show_id` creates a transitive path, but `show_id` is part of the PK and kept deliberately.

---

### 2.11 `movie_reviews`

| Column | Type | Constraints | Rationale |
|--------|------|-------------|-----------|
| `review_id` | `SERIAL` | PK | Surrogate key |
| `movie_id` | `INT` | NOT NULL, FK → movies | Movie being reviewed |
| `customer_id` | `INT` | NOT NULL, FK → customers | Reviewer |
| `rating` | `SMALLINT` | NOT NULL, CHECK 1–10 | Audience star rating |
| `review_text` | `TEXT` | NULLABLE | Optional free-text review |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | When review was submitted |

**FDs:** `review_id → movie_id, customer_id, rating, review_text, created_at`  
**Normal Form:** BCNF — `review_id` is the sole determinant. We allow a customer to review the same movie multiple times (after different viewings), so `(movie_id, customer_id)` is NOT a candidate key.

---

## 3. Functional Dependencies & Normal Form Summary

| Table | Highest NF | Notes |
|-------|-----------|-------|
| `cities` | BCNF | Trivial; one candidate key |
| `venues` | BCNF | Chain denormalized intentionally |
| `screens` | BCNF | `total_seats` denormalized |
| `seats` | BCNF | Composite alternate key `(screen_id, row_label, seat_number)` |
| `movies` | BCNF | Straightforward |
| `shows` | 3NF* | `ends_at` transitively derived via `movie_id.duration_min`; kept for performance |
| `customers` | BCNF | Three candidate keys |
| `offers` | BCNF | Natural PK |
| `bookings` | BCNF* | `ticket_amount` derivable from `booking_seats`; kept for performance |
| `booking_seats` | BCNF* | `show_id` redundant but part of PK by design |
| `movie_reviews` | BCNF | Multiple reviews per customer per movie allowed |

> \* These tables technically violate strict 3NF/BCNF due to designed-in denormalizations. Each is documented and justified in §5.

---

## 4. ER Diagram Description

See `diagrams/er_diagram.md` for the full Mermaid ER diagram. Summary of relationships:

```
cities ──< venues ──< screens ──< seats
                         │
                       shows >── movies
                         │
                 bookings >── customers
                         │
              booking_seats (associative between bookings and seats)
                         │
              movie_reviews (between movies and customers)
                         │
                 bookings >──○ offers (nullable FK)
```

Cardinalities:
- One **city** has many **venues**; one **venue** has many **screens**; one **screen** has many **seats**.
- One **screen** can host many **shows**; one **movie** appears in many **shows**.
- One **customer** makes many **bookings**; one **show** has many **bookings**.
- One **booking** may reference zero or one **offer**.
- One **booking** has many **booking_seats**; each **booking_seat** points to one **seat** and one **show**.
- One **customer** writes many **movie_reviews**; one **movie** receives many **movie_reviews**.

---

## 5. Denormalization Notes

### 5.1 Justified Derived / Redundant Columns

| Column | Derivable From | Why Kept |
|--------|---------------|----------|
| `screens.total_seats` | `COUNT(*) FROM seats WHERE screen_id=?` | Occupancy queries aggregate across thousands of shows; computing the count every time would be expensive. Updated by trigger when seats are added/removed. |
| `shows.ends_at` | `shows.starts_at + movies.duration_min * interval '1 minute'` | Required by the exclusion constraint (`tstzrange`) for overlap detection. Computing it inline in the gist index would be non-trivial. |
| `bookings.ticket_amount` | `SUM(booking_seats.price) WHERE booking_id=?` | Customer-facing booking summary must load instantly; avoids a join to `booking_seats` on every page view. |

### 5.2 Intentional Non-Normalization

| Design Choice | Justification |
|---------------|--------------|
| `venues.chain` stored as VARCHAR | A separate `chains` lookup table would add a FK and join for every venue query. The chain list is small and stable (< 20 brands); embedding it simplifies queries without meaningful redundancy. |
| `booking_seats.show_id` (redundant) | The PK `(show_id, seat_id)` is the ONLY way to prevent double-booking at the DB level without a complex trigger. Without `show_id` in `booking_seats`, the PK would just be `seat_id`, which would prevent a seat from ever being rebooked after a cancellation. |

---

## 6. Integrity Checks

Three integrity checks are run after data loading (see `sql/02_load_data.sql`):

### Check 1 — Seat Belongs to the Correct Screen
```sql
SELECT COUNT(*) AS violations
FROM booking_seats bs
JOIN bookings b ON b.booking_id = bs.booking_id
JOIN shows s ON s.show_id = b.show_id
JOIN seats se ON se.seat_id = bs.seat_id
WHERE se.screen_id <> s.screen_id;
```
**Expected:** 0 violations. Any non-zero count means a seat from the wrong auditorium was booked.

### Check 2 — `num_tickets` Matches Actual Seat Count
```sql
SELECT COUNT(*) AS mismatches
FROM bookings b
LEFT JOIN (SELECT booking_id, COUNT(*) AS seat_count FROM booking_seats GROUP BY booking_id) bs
  ON bs.booking_id = b.booking_id
WHERE b.status IN ('CONFIRMED', 'PENDING')
  AND b.num_tickets <> COALESCE(bs.seat_count, 0);
```
**Expected:** 0 mismatches. CANCELLED bookings are excluded because their `booking_seats` rows are deleted by design.

### Check 3 — No Orphaned Shows
```sql
SELECT COUNT(*) AS orphan_shows
FROM shows s
WHERE NOT EXISTS (SELECT 1 FROM movies m WHERE m.movie_id = s.movie_id)
   OR NOT EXISTS (SELECT 1 FROM screens sc WHERE sc.screen_id = s.screen_id);
```
**Expected:** 0 orphans. FK constraints should prevent this, but the check verifies data-load order correctness.

| Check | Expected Result | Actual Result (post-load) |
|-------|----------------|--------------------------|
| Check 1: Seat–screen mismatch | 0 | *(to be filled after load)* |
| Check 2: num_tickets mismatch | 0 | *(to be filled after load)* |
| Check 3: Orphan shows | 0 | *(to be filled after load)* |

---

## 7. Known Data Problems

### R13 — The NULL Offer Code Trap

**Problem statement context:** To find offers that have *never* been redeemed, one might write:

```sql
-- WRONG: returns empty set when ANY booking has offer_code IS NULL
SELECT offer_code FROM offers
WHERE offer_code NOT IN (SELECT offer_code FROM bookings);
```

**Root cause:** `NOT IN` with a subquery that returns any `NULL` value causes the entire `NOT IN` predicate to evaluate to `UNKNOWN` (not `TRUE`) for every row, because SQL's three-valued logic propagates NULL. Since `bookings.offer_code` is nullable (bookings without an offer code have `NULL`), the subquery always contains at least one `NULL`, making `NOT IN` return no rows at all.

**Correct query using `NOT EXISTS`:**
```sql
SELECT o.offer_code
FROM offers o
WHERE NOT EXISTS (
    SELECT 1
    FROM bookings b
    WHERE b.offer_code = o.offer_code
      AND b.status = 'CONFIRMED'
);
```

**Alternative correct form (filtering NULLs explicitly):**
```sql
SELECT offer_code FROM offers
WHERE offer_code NOT IN (
    SELECT offer_code FROM bookings WHERE offer_code IS NOT NULL
);
```

**Impact:** Any analytics query or report that uses the naive `NOT IN` pattern on `bookings.offer_code` will silently return an incorrect (empty) result set. This is classified as a **semantic bug** — the schema is not at fault, but query authors must be aware that `offer_code` is nullable.

**Mitigation:** Code reviews should flag `NOT IN (SELECT ...)` patterns on nullable columns. Use `NOT EXISTS` as the standard pattern.
