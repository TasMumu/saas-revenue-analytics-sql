-- 7. Sessionization: how long and how deep are product sessions on each plan?
-- A new session starts after 30 minutes without an event. Each session is matched to the plan the
-- account was on when it started (a point-in-time join), so upgrades do not rewrite history.
-- Techniques: LAG gap detection, running SUM to number sessions, range join to type 2 history, percentiles

WITH flagged AS (
    SELECT e.user_id, u.account_id, e.event_time,
           CASE WHEN e.event_time - LAG(e.event_time) OVER (PARTITION BY e.user_id ORDER BY e.event_time)
                     <= INTERVAL '30 minutes' THEN 0 ELSE 1 END AS starts_session
    FROM events e
    JOIN users u ON u.user_id = e.user_id
),
numbered AS (
    SELECT user_id, account_id, event_time,
           SUM(starts_session) OVER (PARTITION BY user_id ORDER BY event_time
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS session_no
    FROM flagged
),
sessions AS (
    SELECT user_id, account_id, session_no,
           MIN(event_time) AS started_at,
           MAX(event_time) AS ended_at,
           COUNT(*)        AS events
    FROM numbered
    GROUP BY user_id, account_id, session_no
),
sessions_with_plan AS (
    SELECT COALESCE(s.plan, 'Trial or lapsed') AS plan,
           se.user_id,
           se.events,
           EXTRACT(EPOCH FROM (se.ended_at - se.started_at)) / 60.0 AS minutes
    FROM sessions se
    LEFT JOIN subscriptions s
      ON s.account_id = se.account_id
     AND s.valid_from <= CAST(se.started_at AS date)
     AND (s.valid_to IS NULL OR s.valid_to > CAST(se.started_at AS date))
)
SELECT plan,
       COUNT(*)                                                                      AS sessions,
       ROUND(AVG(events), 1)                                                         AS avg_events,
       ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY minutes) AS numeric), 1) AS median_minutes,
       ROUND(CAST(percentile_cont(0.9) WITHIN GROUP (ORDER BY minutes) AS numeric), 1) AS p90_minutes,
       ROUND(1.0 * COUNT(*) / COUNT(DISTINCT user_id), 1)                            AS sessions_per_user
FROM sessions_with_plan
GROUP BY plan
ORDER BY CASE plan WHEN 'Starter' THEN 1 WHEN 'Growth' THEN 2 WHEN 'Scale' THEN 3 ELSE 4 END;
