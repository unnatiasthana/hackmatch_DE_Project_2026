# ER Diagram — BookMyShow Ticketing System

> **Note:** This file contains a [Mermaid](https://mermaid.js.org/) `erDiagram` block.  
> Render it with any Mermaid-compatible viewer (e.g., the Mermaid Live Editor at https://mermaid.live, GitHub Markdown preview, VS Code Mermaid extension, or `mmdc` CLI to export to PNG).  
> To generate the PNG: `mmdc -i diagrams/er_diagram.md -o diagrams/er_diagram.png`

```mermaid
erDiagram

    cities {
        int    city_id    PK
        string city_name
        string state
    }

    venues {
        int    venue_id    PK
        string venue_name
        int    city_id     FK
        string chain
        string address
    }

    screens {
        int     screen_id    PK
        int     venue_id     FK
        string  screen_name
        string  screen_type
        int     total_seats
    }

    seats {
        int     seat_id      PK
        int     screen_id    FK
        char    row_label
        int     seat_number
        string  seat_class
    }

    movies {
        int     movie_id      PK
        string  title
        string  language
        char    certificate
        int     duration_min
        date    release_date
    }

    shows {
        int      show_id      PK
        int      movie_id     FK
        int      screen_id    FK
        datetime starts_at
        datetime ends_at
        string   format
        decimal  base_price
    }

    customers {
        int      customer_id    PK
        string   full_name
        string   email
        string   phone
        int      city_id        FK
        datetime created_at
    }

    offers {
        string   offer_code    PK
        string   description
        decimal  discount_pct
        decimal  max_discount
        date     valid_from
        date     valid_to
    }

    bookings {
        int      booking_id       PK
        string   booking_code
        int      customer_id      FK
        int      show_id          FK
        datetime booked_at
        int      num_tickets
        decimal  ticket_amount
        decimal  convenience_fee
        decimal  fnb_amount
        string   offer_code       FK
        decimal  discount
        decimal  total_amount
        string   payment_method
        string   status
    }

    booking_seats {
        int     booking_id    FK
        int     show_id       FK
        int     seat_id       FK
        decimal price
    }

    movie_reviews {
        int      review_id      PK
        int      movie_id       FK
        int      customer_id    FK
        int      rating
        string   review_text
        datetime created_at
    }

    %% -------------------------------------------------------------------------
    %% Relationships
    %% -------------------------------------------------------------------------

    cities      ||--o{  venues         : "has"
    venues      ||--o{  screens        : "contains"
    screens     ||--o{  seats          : "has"
    screens     ||--o{  shows          : "scheduled on"
    movies      ||--o{  shows          : "screened as"
    cities      ||--o{  customers      : "home city of"
    customers   ||--o{  bookings       : "makes"
    shows       ||--o{  bookings       : "has"
    offers      |o--o{  bookings       : "applied to"
    bookings    ||--o{  booking_seats  : "reserves"
    shows       ||--o{  booking_seats  : "seat held for"
    seats       ||--o{  booking_seats  : "assigned in"
    movies      ||--o{  movie_reviews  : "receives"
    customers   ||--o{  movie_reviews  : "writes"
```

---

## Relationship Notes

| Relationship | Cardinality | Notes |
|---|---|---|
| `cities` → `venues` | 1 : Many | A city has zero or more venues; each venue belongs to exactly one city |
| `venues` → `screens` | 1 : Many | A venue contains one or more screens (auditoriums) |
| `screens` → `seats` | 1 : Many | A screen has many physical seats |
| `screens` → `shows` | 1 : Many | A screen hosts many shows over time (non-overlapping, enforced by exclusion constraint) |
| `movies` → `shows` | 1 : Many | A movie appears in many scheduled shows |
| `cities` → `customers` | 1 : Many | A customer's home city; a city has many registered customers |
| `customers` → `bookings` | 1 : Many | A customer makes many bookings over time |
| `shows` → `bookings` | 1 : Many | A show receives many bookings (from different customers) |
| `offers` → `bookings` | 0..1 : Many | An offer is optionally applied to a booking; a booking has at most one offer (nullable FK) |
| `bookings` → `booking_seats` | 1 : Many | A booking reserves one or more seats |
| `shows` → `booking_seats` | 1 : Many | A show has many seat assignment records across all bookings |
| `seats` → `booking_seats` | 1 : Many | A seat can be booked in many shows over time (but only once per show — enforced by PK) |
| `movies` → `movie_reviews` | 1 : Many | A movie receives many audience reviews |
| `customers` → `movie_reviews` | 1 : Many | A customer can write multiple reviews (for different movies or repeat viewings) |
