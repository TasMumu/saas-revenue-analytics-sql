-- 3. MRR bridge: what moved revenue from one month end to the next
-- Splits each month's change into new, reactivation, expansion, contraction and churn.
-- Opening MRR + all movements = closing MRR, and each closing MRR is the next month's opening MRR.
-- Techniques: account x month grid, LAG, a running MAX over prior rows to tell new from reactivated

WITH months AS (
    SELECT (DATE '2023-01-01' + n * INTERVAL '1 month')::date AS month_start
    FROM generate_series(0, 29) AS g(n)
),
month_ends AS (
    SELECT month_start, (month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end
    FROM months
),
account_months AS (
    -- every paying account in every month, with 0 when it had no subscription at month end
    SELECT a.account_id, m.month_start, COALESCE(s.monthly_price, 0) AS mrr
    FROM month_ends m
    CROSS JOIN (SELECT DISTINCT account_id FROM subscriptions) a
    LEFT JOIN subscriptions s
      ON s.account_id = a.account_id
     AND s.valid_from <= m.month_end
     AND (s.valid_to IS NULL OR s.valid_to > m.month_end)
),
movements AS (
    SELECT month_start, mrr,
           COALESCE(LAG(mrr) OVER w, 0) AS prev_mrr,
           COALESCE(MAX(mrr) OVER (PARTITION BY account_id ORDER BY month_start
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS best_prior_mrr
    FROM account_months
    WINDOW w AS (PARTITION BY account_id ORDER BY month_start)
),
classified AS (
    SELECT month_start, mrr, prev_mrr,
           CASE WHEN prev_mrr = 0 AND mrr > 0 AND best_prior_mrr = 0 THEN 'new'
                WHEN prev_mrr = 0 AND mrr > 0                        THEN 'reactivation'
                WHEN prev_mrr > 0 AND mrr = 0                        THEN 'churn'
                WHEN mrr > prev_mrr                                  THEN 'expansion'
                WHEN mrr < prev_mrr                                  THEN 'contraction'
           END AS movement
    FROM movements
)
SELECT month_start                                                              AS month,
       SUM(prev_mrr)                                                            AS opening_mrr,
       COALESCE(SUM(mrr - prev_mrr) FILTER (WHERE movement = 'new'), 0)          AS new_mrr,
       COALESCE(SUM(mrr - prev_mrr) FILTER (WHERE movement = 'reactivation'), 0) AS reactivation_mrr,
       COALESCE(SUM(mrr - prev_mrr) FILTER (WHERE movement = 'expansion'), 0)    AS expansion_mrr,
       COALESCE(SUM(mrr - prev_mrr) FILTER (WHERE movement = 'contraction'), 0)  AS contraction_mrr,
       COALESCE(SUM(mrr - prev_mrr) FILTER (WHERE movement = 'churn'), 0)        AS churned_mrr,
       SUM(mrr)                                                                 AS closing_mrr,
       COUNT(*) FILTER (WHERE movement = 'new')                                 AS new_accounts,
       COUNT(*) FILTER (WHERE movement = 'churn')                               AS churned_accounts
FROM classified
GROUP BY month_start
ORDER BY month_start;
