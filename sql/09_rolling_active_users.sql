-- 9. Daily, weekly and monthly active users for Q2 2025, and stickiness (DAU / MAU)
-- Rolling distinct counts cannot use a window COUNT(DISTINCT), so each day is joined to the
-- user-days in its trailing 28-day range and counted with FILTER.
-- Techniques: date spine, range self-join, COUNT(DISTINCT) with FILTER, moving average window

WITH days AS (
    SELECT DATE '2025-04-01' + CAST(n AS integer) AS day
    FROM generate_series(0, 90) AS g(n)
),
user_days AS (
    SELECT DISTINCT user_id, CAST(event_time AS date) AS day
    FROM events
    WHERE event_time >= TIMESTAMP '2025-03-01'
),
rolling AS (
    SELECT d.day,
           COUNT(DISTINCT ud.user_id) FILTER (WHERE ud.day = d.day)    AS dau,
           COUNT(DISTINCT ud.user_id) FILTER (WHERE ud.day > d.day - 7) AS wau,
           COUNT(DISTINCT ud.user_id)                                   AS mau
    FROM days d
    JOIN user_days ud
      ON ud.day >  d.day - 28
     AND ud.day <= d.day
    GROUP BY d.day
)
SELECT day,
       dau,
       wau,
       mau,
       ROUND(100.0 * dau / NULLIF(mau, 0), 1)                                         AS dau_mau_pct,
       ROUND(AVG(dau) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS dau_7day_avg
FROM rolling
ORDER BY day;
