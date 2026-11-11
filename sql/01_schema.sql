-- =============================================================================
-- BookMyShow Ticketing System — Schema DDL
-- File:    sql/01_schema.sql
-- Phase:   CP1
-- DB:      PostgreSQL 15
-- Schema:  bms
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS bms;

SET search_path TO bms;

-- =============================================================================
-- TABLE: cities
-- =============================================================================
CREATE TABLE cities (
    city_id    SERIAL          PRIMARY KEY,
    city_name  VARCHAR(100)    NOT NULL,
    state      VARCHAR(100)    NOT NULL
);

COMMENT ON TABLE  cities           IS 'Master list of cities where venues operate';
COMMENT ON COLUMN cities.city_id   IS 'Surrogate primary key';
COMMENT ON COLUMN cities.city_name IS 'Display name of the city (e.g., Mumbai)';
COMMENT ON COLUMN cities.state     IS 'State the city belongs to';

-- =============================================================================
-- TABLE: venues
-- =============================================================================
CREATE TABLE venues (
    venue_id    SERIAL          PRIMARY KEY,
    venue_name  VARCHAR(200)    NOT NULL,
    city_id     INT             NOT NULL,
    chain       VARCHAR(100)    NOT NULL,
    address     TEXT            NOT NULL,

    CONSTRAINT fk_venues_city
        FOREIGN KEY (city_id) REFERENCES cities (city_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  venues            IS 'Physical multiplex/cinema locations';
COMMENT ON COLUMN venues.chain      IS 'Multiplex brand: PVR, INOX, Cinepolis, Miraj, Carnival, etc.';
COMMENT ON COLUMN venues.address    IS 'Full street address of the venue';

-- =============================================================================
-- TABLE: screens
-- =============================================================================
CREATE TABLE screens (
    screen_id    SERIAL          PRIMARY KEY,
    venue_id     INT             NOT NULL,
    screen_name  VARCHAR(100)    NOT NULL,
    screen_type  VARCHAR(20)     NOT NULL,
    total_seats  SMALLINT        NOT NULL,

    CONSTRAINT fk_screens_venue
        FOREIGN KEY (venue_id) REFERENCES venues (venue_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_screens_type
        CHECK (screen_type IN ('STANDARD', 'IMAX', '4DX', 'SCREENX', 'DOLBY', 'LUXE', 'MX4D')),

    CONSTRAINT chk_screens_total_seats
        CHECK (total_seats > 0)
);

COMMENT ON TABLE  screens              IS 'Individual auditoriums within a venue';
COMMENT ON COLUMN screens.screen_type  IS 'Technology: STANDARD, IMAX, 4DX, SCREENX, DOLBY, LUXE, MX4D';
COMMENT ON COLUMN screens.total_seats  IS 'Denormalised seat count — kept for fast occupancy calculations. Must equal COUNT(*) of seats for this screen.';

-- =============================================================================
-- TABLE: seats
-- =============================================================================
CREATE TABLE seats (
    seat_id      SERIAL          PRIMARY KEY,
    screen_id    INT             NOT NULL,
    row_label    CHAR(1)         NOT NULL,
    seat_number  SMALLINT        NOT NULL,
    seat_class   VARCHAR(20)     NOT NULL,

    CONSTRAINT fk_seats_screen
        FOREIGN KEY (screen_id) REFERENCES screens (screen_id)
        ON DELETE RESTRICT,

    -- Physical address of a seat within a screen must be unique
    CONSTRAINT uq_seats_screen_row_num
        UNIQUE (screen_id, row_label, seat_number),

    CONSTRAINT chk_seats_class
        CHECK (seat_class IN ('CLASSIC', 'PRIME', 'RECLINER'))
);

COMMENT ON TABLE  seats             IS 'Individual physical seats within a screen';
COMMENT ON COLUMN seats.row_label   IS 'Single character row identifier, A–Z';
COMMENT ON COLUMN seats.seat_number IS 'Column number of the seat within its row';
COMMENT ON COLUMN seats.seat_class  IS 'Pricing tier: CLASSIC, PRIME, or RECLINER';

-- =============================================================================
-- TABLE: movies
-- =============================================================================
CREATE TABLE movies (
    movie_id      SERIAL          PRIMARY KEY,
    title         VARCHAR(300)    NOT NULL,
    language      VARCHAR(50)     NOT NULL,
    certificate   CHAR(2)         NOT NULL,
    duration_min  SMALLINT        NOT NULL,
    release_date  DATE            NOT NULL,

    CONSTRAINT chk_movies_certificate
        CHECK (certificate IN ('U', 'UA', 'A', 'S')),

    CONSTRAINT chk_movies_duration
        CHECK (duration_min > 0)
);

COMMENT ON TABLE  movies               IS 'Movie/film master catalogue';
COMMENT ON COLUMN movies.certificate   IS 'Censor board rating: U (universal), UA (parental guidance), A (adults only), S (specialised)';
COMMENT ON COLUMN movies.duration_min  IS 'Runtime in minutes';
COMMENT ON COLUMN movies.release_date  IS 'Theatrical release date in India';

-- =============================================================================
-- TABLE: shows
-- =============================================================================
CREATE TABLE shows (
    show_id     SERIAL              PRIMARY KEY,
    movie_id    INT                 NOT NULL,
    screen_id   INT                 NOT NULL,
    starts_at   TIMESTAMPTZ         NOT NULL,
    ends_at     TIMESTAMPTZ         NOT NULL,
    format      VARCHAR(10)         NOT NULL,
    base_price  NUMERIC(10,2)       NOT NULL,

    CONSTRAINT fk_shows_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_shows_screen
        FOREIGN KEY (screen_id) REFERENCES screens (screen_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_shows_format
        CHECK (format IN ('2D', '3D', 'IMAX', '4DX', 'DOLBY', 'SCREENX')),

    CONSTRAINT chk_shows_ends_after_starts
        CHECK (ends_at > starts_at),

    CONSTRAINT chk_shows_base_price
        CHECK (base_price >= 0),

    -- Exclusion constraint: no two shows on the same screen may overlap in time.
    -- Uses btree_gist extension.
    -- tstzrange(starts_at, ends_at, '[)') = half-open interval [starts_at, ends_at)
    CONSTRAINT excl_shows_no_screen_overlap
        EXCLUDE USING gist (
            screen_id WITH =,
            tstzrange(starts_at, ends_at, '[)') WITH &&
        )
);

COMMENT ON TABLE  shows            IS 'Scheduled screenings of a movie on a screen';
COMMENT ON COLUMN shows.ends_at    IS 'Derived from starts_at + movies.duration_min but stored for the gist exclusion constraint and query performance';
COMMENT ON COLUMN shows.format     IS 'Screening format: 2D, 3D, IMAX, 4DX, DOLBY, SCREENX';
COMMENT ON COLUMN shows.base_price IS 'Base ticket price in INR before seat-class multiplier';

-- =============================================================================
-- TABLE: customers
-- =============================================================================
CREATE TABLE customers (
    customer_id  SERIAL          PRIMARY KEY,
    full_name    VARCHAR(200)    NOT NULL,
    email        VARCHAR(255)    NOT NULL,
    phone        VARCHAR(15)     NOT NULL,
    city_id      INT             NOT NULL,
    created_at   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_customers_email
        UNIQUE (email),

    CONSTRAINT uq_customers_phone
        UNIQUE (phone),

    CONSTRAINT fk_customers_city
        FOREIGN KEY (city_id) REFERENCES cities (city_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  customers             IS 'Registered BookMyShow customer accounts';
COMMENT ON COLUMN customers.city_id     IS 'Home city used as default for show search';
COMMENT ON COLUMN customers.created_at  IS 'Account registration timestamp';

-- =============================================================================
-- TABLE: offers
-- =============================================================================
CREATE TABLE offers (
    offer_code    VARCHAR(20)     PRIMARY KEY,
    description   TEXT            NOT NULL,
    discount_pct  NUMERIC(5,2)    NOT NULL,
    max_discount  NUMERIC(10,2)   NOT NULL,
    valid_from    DATE            NOT NULL,
    valid_to      DATE            NOT NULL,

    CONSTRAINT chk_offers_discount_pct
        CHECK (discount_pct BETWEEN 0 AND 100),

    CONSTRAINT chk_offers_max_discount
        CHECK (max_discount >= 0),

    CONSTRAINT chk_offers_dates
        CHECK (valid_to >= valid_from)
);

COMMENT ON TABLE  offers               IS 'Promotional offer / promo codes';
COMMENT ON COLUMN offers.offer_code    IS 'Natural primary key — the code customers enter (e.g., BLOCKBUSTER25)';
COMMENT ON COLUMN offers.discount_pct  IS 'Percentage discount applied to ticket_amount';
COMMENT ON COLUMN offers.max_discount  IS 'Maximum discount in INR (cap). Actual discount = MIN(ticket_amount * discount_pct / 100, max_discount)';

-- =============================================================================
-- TABLE: bookings
-- =============================================================================
CREATE TABLE bookings (
    booking_id       SERIAL          PRIMARY KEY,
    booking_code     VARCHAR(10)     NOT NULL,
    customer_id      INT             NOT NULL,
    show_id          INT             NOT NULL,
    booked_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    num_tickets      SMALLINT        NOT NULL,
    ticket_amount    NUMERIC(10,2)   NOT NULL,
    convenience_fee  NUMERIC(10,2)   NOT NULL,
    fnb_amount       NUMERIC(10,2)   NOT NULL,
    offer_code       VARCHAR(20)     NULL,       -- nullable: no offer used when NULL
    discount         NUMERIC(10,2)   NOT NULL,
    total_amount     NUMERIC(10,2)   NOT NULL,
    payment_method   VARCHAR(20)     NOT NULL,
    status           VARCHAR(20)     NOT NULL,

    -- Unique readable reference code shown to customers
    CONSTRAINT uq_bookings_code
        UNIQUE (booking_code),

    -- Format: "BMS" followed by exactly 7 uppercase hexadecimal characters
    -- Total length = 10 characters
    CONSTRAINT chk_bookings_code_format
        CHECK (booking_code ~ '^BMS[0-9A-F]{7}$'),

    CONSTRAINT chk_bookings_status
        CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELLED')),

    CONSTRAINT chk_bookings_payment_method
        CHECK (payment_method IN ('UPI', 'CREDIT_CARD', 'DEBIT_CARD', 'WALLET', 'NET_BANKING', 'GIFT_CARD')),

    CONSTRAINT chk_bookings_num_tickets
        CHECK (num_tickets > 0),

    CONSTRAINT chk_bookings_total_amount
        CHECK (total_amount >= 0),

    CONSTRAINT chk_bookings_discount
        CHECK (discount >= 0),

    CONSTRAINT chk_bookings_ticket_amount
        CHECK (ticket_amount >= 0),

    CONSTRAINT chk_bookings_convenience_fee
        CHECK (convenience_fee >= 0),

    CONSTRAINT chk_bookings_fnb_amount
        CHECK (fnb_amount >= 0),

    CONSTRAINT fk_bookings_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_bookings_show
        FOREIGN KEY (show_id) REFERENCES shows (show_id)
        ON DELETE RESTRICT,

    -- offer_code is nullable; FK only enforced when non-NULL (PostgreSQL handles this correctly)
    CONSTRAINT fk_bookings_offer
        FOREIGN KEY (offer_code) REFERENCES offers (offer_code)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  bookings                 IS 'Ticket booking transactions';
COMMENT ON COLUMN bookings.booking_code    IS 'Customer-facing reference code. Format: BMS + 7 uppercase hex chars (e.g., BMS0004F28)';
COMMENT ON COLUMN bookings.ticket_amount   IS 'Sum of booking_seats.price for this booking — denormalised for query performance';
COMMENT ON COLUMN bookings.fnb_amount      IS 'Food & beverage pre-order amount';
COMMENT ON COLUMN bookings.offer_code      IS 'NULL when no promo code was applied. CAUTION: use NOT EXISTS (not NOT IN) when querying unredeemed offers — NOT IN returns empty when any offer_code IS NULL';
COMMENT ON COLUMN bookings.discount        IS 'Actual discount applied in INR (after max_discount cap). Zero when no offer used.';
COMMENT ON COLUMN bookings.status          IS 'PENDING: payment in progress; CONFIRMED: paid; CANCELLED: refunded/voided';

-- =============================================================================
-- TABLE: booking_seats
-- =============================================================================
-- NOTE on the show_id consistency requirement (Requirement R-booking_seats):
--   The requirement states that booking_seats.show_id must equal bookings.show_id
--   for the same booking_id. This CANNOT be enforced by a simple CHECK constraint
--   because CHECK constraints cannot reference other tables. Options are:
--     1. Enforce at the application layer (preferred for this phase).
--     2. Use a trigger (BEFORE INSERT/UPDATE ON booking_seats) that verifies
--        NEW.show_id = (SELECT show_id FROM bookings WHERE booking_id = NEW.booking_id).
--     3. Add a FK on (booking_id, show_id) pointing to a UNIQUE(booking_id, show_id)
--        on bookings — but bookings only has booking_id as PK, so show_id would need
--        to be part of a composite unique key there, which is redundant since show_id
--        is already determined by booking_id.
--   For this schema phase we document the constraint and enforce it via a trigger
--   (trigger body omitted in CP1; to be added in CP2).
-- =============================================================================

CREATE TABLE booking_seats (
    booking_id  INT             NOT NULL,
    show_id     INT             NOT NULL,
    seat_id     INT             NOT NULL,
    price       NUMERIC(10,2)   NOT NULL,

    -- PRIMARY KEY on (show_id, seat_id) is the core double-booking guard:
    -- a seat cannot appear twice for the same show, regardless of booking.
    CONSTRAINT pk_booking_seats
        PRIMARY KEY (show_id, seat_id),

    CONSTRAINT chk_booking_seats_price
        CHECK (price > 0),

    -- CASCADE: when a booking is deleted (e.g., hard-delete after cancellation),
    -- its seat assignments are removed automatically.
    CONSTRAINT fk_bs_booking
        FOREIGN KEY (booking_id) REFERENCES bookings (booking_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_bs_show
        FOREIGN KEY (show_id) REFERENCES shows (show_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_bs_seat
        FOREIGN KEY (seat_id) REFERENCES seats (seat_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  booking_seats          IS 'Individual seat assignments for each booking. PK (show_id, seat_id) prevents double-booking a seat per show.';
COMMENT ON COLUMN booking_seats.show_id  IS 'Redundant (derivable via bookings.show_id) but required for the PK and for join performance. Must equal bookings.show_id — enforced by application/trigger.';
COMMENT ON COLUMN booking_seats.price    IS 'Price actually paid for this seat (may differ from base_price due to class multipliers and surge pricing)';

-- =============================================================================
-- TABLE: movie_reviews
-- =============================================================================
CREATE TABLE movie_reviews (
    review_id    SERIAL          PRIMARY KEY,
    movie_id     INT             NOT NULL,
    customer_id  INT             NOT NULL,
    rating       SMALLINT        NOT NULL,
    review_text  TEXT            NULL,       -- nullable: rating-only reviews allowed
    created_at   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_reviews_rating
        CHECK (rating BETWEEN 1 AND 10),

    CONSTRAINT fk_reviews_movie
        FOREIGN KEY (movie_id) REFERENCES movies (movie_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_reviews_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  movie_reviews              IS 'Audience reviews and ratings for movies';
COMMENT ON COLUMN movie_reviews.rating       IS 'Integer score 1 (worst) to 10 (best)';
COMMENT ON COLUMN movie_reviews.review_text  IS 'Optional free-text review body. NULL when customer submits a rating-only review.';

-- =============================================================================
-- INDEXES for common query patterns
-- =============================================================================

-- Show search by city + movie + date range (P1)
CREATE INDEX idx_shows_movie_id      ON shows (movie_id);
CREATE INDEX idx_shows_screen_id     ON shows (screen_id);
CREATE INDEX idx_shows_starts_at     ON shows (starts_at);

-- Seat availability lookup (P2)
CREATE INDEX idx_booking_seats_booking_id ON booking_seats (booking_id);

-- Revenue reports by customer / show (P5, P8)
CREATE INDEX idx_bookings_customer_id ON bookings (customer_id);
CREATE INDEX idx_bookings_show_id     ON bookings (show_id);
CREATE INDEX idx_bookings_status      ON bookings (status);
CREATE INDEX idx_bookings_booked_at   ON bookings (booked_at);

-- Offer analytics (P6)
CREATE INDEX idx_bookings_offer_code  ON bookings (offer_code) WHERE offer_code IS NOT NULL;

-- Movie reviews (P7)
CREATE INDEX idx_reviews_movie_id     ON movie_reviews (movie_id);
CREATE INDEX idx_reviews_customer_id  ON movie_reviews (customer_id);

-- Venue/screen geography (P1, P5)
CREATE INDEX idx_venues_city_id       ON venues (city_id);
CREATE INDEX idx_screens_venue_id     ON screens (venue_id);
CREATE INDEX idx_seats_screen_id      ON seats (screen_id);
