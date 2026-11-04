-- 2. Monthly recurring revenue (MRR), paying accounts and average revenue per account at each month end
-- Techniques: generated month spine, range join to a type 2 history table, LAG for month-over-month growth

WITH months AS (
    SELECT (DATE '2023-01-01' + n * INTERVAL '1 month')::date AS month_start
    FROM generate_series(0, 29) AS g(n)
),
month_ends AS (
    SELECT month_start,
           (month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end
    FROM months
),
mrr AS (
    -- the subscription row in force on the last day of each month
    SELECT m.month_start,
           COUNT(s.account_id)              AS paying_accounts,
           COALESCE(SUM(s.monthly_price), 0) AS mrr
    FROM month_ends m
    LEFT JOIN subscriptions s
      ON s.valid_from <= m.month_end
     AND (s.valid_to IS NULL OR s.valid_to > m.month_end)
    GROUP BY m.month_start
)
SELECT month_start                                          AS month,
       paying_accounts,
       mrr,
       ROUND(mrr / NULLIF(paying_accounts, 0), 2)           AS arpa,
       ROUND(100.0 * (mrr - LAG(mrr) OVER (ORDER BY month_start))
             / NULLIF(LAG(mrr) OVER (ORDER BY month_start), 0), 1) AS mom_growth_pct
FROM mrr
ORDER BY month_start;
