-- 8. Gaps and islands: each account's longest run of consecutive active weeks
-- An account is active in a week if any of its users logged any event. Consecutive weeks form an
-- "island"; subtracting 7 days x row number gives every week in the same island the same key.
-- Techniques: gaps and islands with ROW_NUMBER, DISTINCT ON to keep each account's best streak

WITH active_weeks AS (
    SELECT DISTINCT u.account_id, CAST(date_trunc('week', e.event_time) AS date) AS week_start
    FROM events e
    JOIN users u ON u.user_id = e.user_id
),
islands AS (
    SELECT account_id, week_start,
           week_start - 7 * CAST(ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY week_start) AS integer) AS island_key
    FROM active_weeks
),
streaks AS (
    SELECT account_id,
           MIN(week_start) AS streak_start,
           MAX(week_start) AS streak_end,
           COUNT(*)        AS streak_weeks
    FROM islands
    GROUP BY account_id, island_key
),
best AS (
    SELECT DISTINCT ON (account_id) account_id, streak_start, streak_end, streak_weeks
    FROM streaks
    ORDER BY account_id, streak_weeks DESC, streak_end DESC
)
SELECT a.company_name,
       b.streak_weeks,
       b.streak_start,
       b.streak_end,
       b.streak_end >= DATE '2025-06-23' AS still_running      -- the last full week of data starts 23 June 2025
FROM best b
JOIN accounts a ON a.account_id = b.account_id
ORDER BY b.streak_weeks DESC, b.streak_end DESC, a.company_name
LIMIT 15;
