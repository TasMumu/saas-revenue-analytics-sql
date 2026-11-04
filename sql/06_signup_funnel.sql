-- 6. Signup funnel by acquisition channel
-- Signup -> activated (connected an integration within 7 days) -> paying within 30 days.
-- Also compares conversion for activated vs not-activated accounts, the case for onboarding work.
-- Techniques: multi-step LEFT JOINs, boolean FILTER aggregates, percentile_cont, GROUPING SETS

WITH activation AS (
    SELECT u.account_id, MIN(e.event_time) AS activated_at
    FROM events e
    JOIN users u ON u.user_id = e.user_id
    WHERE e.event_name = 'integration_connected'
    GROUP BY u.account_id
),
first_paid AS (
    SELECT account_id, MIN(valid_from) AS paid_from
    FROM subscriptions
    GROUP BY account_id
),
funnel AS (
    SELECT a.acquisition_channel,
           COALESCE(act.activated_at < a.signup_date + INTERVAL '8 days', FALSE) AS activated_7d,
           COALESCE(fp.paid_from <= a.signup_date + 30, FALSE)                   AS paid_30d,
           CASE WHEN fp.paid_from <= a.signup_date + 30 THEN fp.paid_from - a.signup_date END AS days_to_paid
    FROM accounts a
    LEFT JOIN activation act ON act.account_id = a.account_id
    LEFT JOIN first_paid fp  ON fp.account_id  = a.account_id
)
SELECT COALESCE(acquisition_channel, 'All channels')                                    AS channel,
       COUNT(*)                                                                          AS signups,
       ROUND(100.0 * COUNT(*) FILTER (WHERE activated_7d) / COUNT(*), 1)                 AS activated_7d_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paid_30d) / COUNT(*), 1)                     AS paid_30d_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paid_30d AND activated_7d)
             / NULLIF(COUNT(*) FILTER (WHERE activated_7d), 0), 1)                       AS paid_pct_if_activated,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paid_30d AND NOT activated_7d)
             / NULLIF(COUNT(*) FILTER (WHERE NOT activated_7d), 0), 1)                   AS paid_pct_if_not_activated,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_paid)                         AS median_days_to_paid
FROM funnel
GROUP BY GROUPING SETS ((acquisition_channel), ())
ORDER BY GROUPING(acquisition_channel), paid_30d_pct DESC;
