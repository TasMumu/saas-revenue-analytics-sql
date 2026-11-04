-- Fernhollow Software (fictional B2B SaaS): schema for the revenue and product analytics queries
-- Written for PostgreSQL 14+. The same file also runs on DuckDB, which the test script uses.

DROP VIEW IF EXISTS events;
DROP TABLE IF EXISTS support_tickets;
DROP TABLE IF EXISTS events_raw;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS accounts;

CREATE TABLE accounts (
    account_id             integer PRIMARY KEY,
    company_name           text    NOT NULL,
    signup_date            date    NOT NULL,
    region                 text    NOT NULL,
    industry               text    NOT NULL,
    acquisition_channel    text    NOT NULL,
    referred_by_account_id integer             -- the account that referred this one, if any
);

-- Plan history as a slowly changing dimension (type 2): one row per plan and seat state.
-- valid_from is inclusive, valid_to is exclusive, and NULL means the row is current.
CREATE TABLE subscriptions (
    subscription_id integer PRIMARY KEY,
    account_id      integer       NOT NULL REFERENCES accounts (account_id),
    plan            text          NOT NULL CHECK (plan IN ('Starter', 'Growth', 'Scale')),
    seats           integer       NOT NULL CHECK (seats > 0),
    monthly_price   numeric(10,2) NOT NULL,
    valid_from      date          NOT NULL,
    valid_to        date,
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE users (
    user_id    integer   PRIMARY KEY,
    account_id integer   NOT NULL REFERENCES accounts (account_id),
    created_at timestamp NOT NULL
);

-- Product events as loaded, including duplicate deliveries from the event pipeline
CREATE TABLE events_raw (
    event_id   integer   PRIMARY KEY,
    user_id    integer   NOT NULL REFERENCES users (user_id),
    event_time timestamp NOT NULL,
    event_name text      NOT NULL
);

CREATE TABLE support_tickets (
    ticket_id         integer   PRIMARY KEY,
    account_id        integer   NOT NULL REFERENCES accounts (account_id),
    priority          text      NOT NULL CHECK (priority IN ('urgent', 'high', 'normal', 'low')),
    opened_at         timestamp NOT NULL,
    first_response_at timestamp,
    resolved_at       timestamp
);

CREATE INDEX subscriptions_account_idx ON subscriptions (account_id, valid_from);
CREATE INDEX events_raw_user_time_idx  ON events_raw (user_id, event_time);
CREATE INDEX tickets_account_idx       ON support_tickets (account_id, opened_at);

-- Clean event stream: keep the first delivery of each (user, time, event) and drop the duplicates.
-- Every product query reads this view, never events_raw.
CREATE VIEW events AS
SELECT event_id, user_id, event_time, event_name
FROM (
    SELECT e.*,
           ROW_NUMBER() OVER (PARTITION BY user_id, event_time, event_name ORDER BY event_id) AS delivery_no
    FROM events_raw e
) d
WHERE delivery_no = 1;
