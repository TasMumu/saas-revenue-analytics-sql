-- 13. Churn-risk watchlist for the customer success team
-- For every paying account on 30 June 2025: product usage in June vs the 30 days before,
-- and recent high-priority tickets. Points add up to a risk score; the top 15 go on the watchlist.
-- Techniques: FILTER windows of time, LATERAL subquery per account, CASE scoring, deterministic ranking

WITH current_subs AS (
    SELECT account_id, plan, seats, monthly_price
    FROM subscriptions
    WHERE valid_to IS NULL
),
usage AS (
    SELECT u.account_id,
           COUNT(*) FILTER (WHERE e.event_time >= TIMESTAMP '2025-06-01')                AS events_last_30d,
           COUNT(*) FILTER (WHERE e.event_time <  TIMESTAMP '2025-06-01')                AS events_prior_30d,
           COUNT(DISTINCT e.user_id) FILTER (WHERE e.event_time >= TIMESTAMP '2025-06-01') AS active_users_last_30d
    FROM events e
    JOIN users u ON u.user_id = e.user_id
    WHERE e.event_time >= TIMESTAMP '2025-05-02'
    GROUP BY u.account_id
),
signals AS (
    SELECT a.account_id, a.company_name, a.region, cs.plan, cs.monthly_price AS mrr,
           COALESCE(us.events_last_30d, 0)       AS events_last_30d,
           COALESCE(us.events_prior_30d, 0)      AS events_prior_30d,
           COALESCE(us.active_users_last_30d, 0) AS active_users_last_30d,
           tk.escalations_90d
    FROM current_subs cs
    JOIN accounts a ON a.account_id = cs.account_id
    LEFT JOIN usage us ON us.account_id = cs.account_id
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS escalations_90d
        FROM support_tickets st
        WHERE st.account_id = cs.account_id
          AND st.priority IN ('urgent', 'high')
          AND st.opened_at >= TIMESTAMP '2025-04-01'
    ) tk
),
scored AS (
    SELECT *,
           ROUND(100.0 * (events_last_30d - events_prior_30d) / NULLIF(events_prior_30d, 0), 0) AS usage_change_pct,
           CASE WHEN events_last_30d = 0                         THEN 50
                WHEN events_last_30d <= 0.5  * events_prior_30d  THEN 35
                WHEN events_last_30d <= 0.75 * events_prior_30d  THEN 20
                ELSE 0 END
         + CASE WHEN escalations_90d >= 2 THEN 25 WHEN escalations_90d = 1 THEN 10 ELSE 0 END
         + CASE WHEN plan = 'Starter' THEN 10 ELSE 0 END AS risk_score
    FROM signals
)
SELECT company_name, region, plan, mrr,
       events_prior_30d, events_last_30d, usage_change_pct,
       active_users_last_30d, escalations_90d, risk_score
FROM scored
ORDER BY risk_score DESC, mrr DESC, account_id
LIMIT 15;
