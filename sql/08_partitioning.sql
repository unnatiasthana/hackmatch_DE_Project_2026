-- =====================================================================
-- 08_partitioning.sql  —  Phase 5: partitioned booking_seats (design for 100x)
-- PostgreSQL 15+
--
-- WHY booking_seats:
--   It is the largest table (300k rows on seed, ~6.0M on large, ~30M at 100x)
--   and every hot query reaches it by show_id: R03 (seat layout), R07/R25
--   (occupancy), W01/W02 (seat lock), W04 (expiry).
--
-- WHY HASH on show_id:
--   * Every real-time access path has `show_id = <value>`, so the planner
--     prunes to exactly ONE partition (see EXPLAIN at the end).
--   * booking_seats has no timestamp column, so RANGE by time is not possible
--     without adding a column; HASH spreads writes evenly, so no single
--     "hot" partition during a release weekend.
--   * 16 partitions: ~375k rows each on large data, ~1.9M each at 100x —
--     small enough for fast VACUUM and index builds per partition.
--
-- PRIMARY-KEY RULE FOR PARTITIONED TABLES:
--   A PRIMARY KEY / UNIQUE constraint on a partitioned table MUST include
--   every partition-key column. Our key is (show_id, seat_id) and the
--   partition key is show_id, so the double-booking guard
--   ("a seat is sold only once per show") is still enforced globally.
--   Partitioning by booking_id instead would NOT be allowed with this PK.
-- =====================================================================

BEGIN;

ALTER TABLE booking_seats RENAME TO booking_seats_old;
ALTER TABLE booking_seats_old RENAME CONSTRAINT pk_booking_seats TO pk_booking_seats_old;

CREATE TABLE booking_seats (
    booking_id  INT            NOT NULL,
    show_id     INT            NOT NULL,
    seat_id     INT            NOT NULL,
    price       NUMERIC(10,2)  NOT NULL,

    CONSTRAINT pk_booking_seats PRIMARY KEY (show_id, seat_id),   -- includes partition key
    CONSTRAINT chk_booking_seats_price_p CHECK (price > 0),
    CONSTRAINT fk_bs_booking_p FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_bs_show_p    FOREIGN KEY (show_id)    REFERENCES shows (show_id)       ON DELETE RESTRICT,
    CONSTRAINT fk_bs_seat_p    FOREIGN KEY (seat_id)    REFERENCES seats (seat_id)       ON DELETE RESTRICT
) PARTITION BY HASH (show_id);

-- 16 hash partitions
DO $$
BEGIN
    FOR i IN 0..15 LOOP
        EXECUTE format(
            'CREATE TABLE booking_seats_p%s PARTITION OF booking_seats
                 FOR VALUES WITH (MODULUS 16, REMAINDER %s);', lpad(i::text, 2, '0'), i);
    END LOOP;
END $$;

-- Secondary indexes are created on the parent and cascade to every partition.
CREATE INDEX idx_booking_seats_p_seat_id    ON booking_seats (seat_id);     -- R17, W02
CREATE INDEX idx_booking_seats_p_booking_id ON booking_seats (booking_id);  -- W04, FK cascade

-- Move the data
INSERT INTO booking_seats (booking_id, show_id, seat_id, price)
SELECT booking_id, show_id, seat_id, price FROM booking_seats_old;

-- Sanity check: row counts must match before dropping the old table
DO $$
DECLARE n_old bigint; n_new bigint;
BEGIN
    SELECT count(*) INTO n_old FROM booking_seats_old;
    SELECT count(*) INTO n_new FROM booking_seats;
    IF n_old <> n_new THEN
        RAISE EXCEPTION 'row count mismatch: old=% new=%', n_old, n_new;
    END IF;
END $$;

DROP TABLE booking_seats_old;

COMMIT;

ANALYZE booking_seats;

-- Per-partition autovacuum (seat-lock expiry W04 deletes rows constantly)
DO $$
BEGIN
    FOR i IN 0..15 LOOP
        EXECUTE format(
            'ALTER TABLE booking_seats_p%s SET (autovacuum_vacuum_scale_factor = 0.02,
                                                autovacuum_analyze_scale_factor = 0.01);',
            lpad(i::text, 2, '0'));
    END LOOP;
END $$;

-- =====================================================================
-- PARTITION PRUNING PROOF  (paste the output into docs/05_scalability_report.md)
-- Expected: only ONE booking_seats_pNN partition appears in the plan.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT se.row_label, se.seat_number, se.seat_class, (bs.seat_id IS NOT NULL) AS sold
FROM shows s
JOIN seats se ON se.screen_id = s.screen_id
LEFT JOIN booking_seats bs ON bs.show_id = s.show_id AND bs.seat_id = se.seat_id
WHERE s.show_id = 144446
ORDER BY se.row_label DESC, se.seat_number;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM booking_seats WHERE show_id = 144446;

-- Partition sizes
SELECT c.relname AS partition, pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       (SELECT count(*) FROM pg_inherits i WHERE i.inhparent = c.oid) AS sub
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'booking_seats'::regclass
ORDER BY c.relname;
