-- 4. Logo retention by quarterly cohort
-- Of the accounts that started paying in a quarter, what share still paid 1, 3, 6, 9 and 12 months
-- after their own first paid month? Cells a cohort has not fully reached yet stay empty.
-- Techniques: month arithmetic, pivot with FILTER aggregates, CASE to blank unobservable cells

WITH months AS (
    SELECT (DATE '2023-01-01' + n * INTERVAL '1 month')::date AS month_start
    FROM generate_series(0, 29) AS g(n)
),
month_ends AS (
    SELECT month_start, (month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end
    FROM months
),
first_paid AS (
    SELECT account_id,
           date_trunc('month', MIN(valid_from))::date   AS first_month,
           date_trunc('quarter', MIN(valid_from))::date AS cohort_quarter
    FROM subscriptions
    GROUP BY account_id
),
paying_months AS (
    SELECT DISTINCT s.account_id, m.month_start
    FROM month_ends m
    JOIN subscriptions s
      ON s.valid_from <= m.month_end
     AND (s.valid_to IS NULL OR s.valid_to > m.month_end)
),
activity AS (
    SELECT f.cohort_quarter, f.account_id,
           (EXTRACT(YEAR FROM p.month_start) - EXTRACT(YEAR FROM f.first_month)) * 12
         + (EXTRACT(MONTH FROM p.month_start) - EXTRACT(MONTH FROM f.first_month)) AS months_since_start
    FROM first_paid f
    JOIN paying_months p ON p.account_id = f.account_id
),
cohorts AS (
    -- months of history after the cohort's last start month (June 2025 is the last month of data)
    SELECT cohort_quarter,
           COUNT(*) AS cohort_size,
           (2025 - EXTRACT(YEAR FROM cohort_quarter)) * 12 + 6 - (EXTRACT(MONTH FROM cohort_quarter) + 2) AS months_observed
    FROM first_paid
    GROUP BY cohort_quarter
)
SELECT c.cohort_quarter,
       c.cohort_size,
       CASE WHEN c.months_observed >= 1  THEN ROUND(100.0 * COUNT(DISTINCT a.account_id) FILTER (WHERE a.months_since_start = 1)  / c.cohort_size, 1) END AS month_1_pct,
       CASE WHEN c.months_observed >= 3  THEN ROUND(100.0 * COUNT(DISTINCT a.account_id) FILTER (WHERE a.months_since_start = 3)  / c.cohort_size, 1) END AS month_3_pct,
       CASE WHEN c.months_observed >= 6  THEN ROUND(100.0 * COUNT(DISTINCT a.account_id) FILTER (WHERE a.months_since_start = 6)  / c.cohort_size, 1) END AS month_6_pct,
       CASE WHEN c.months_observed >= 9  THEN ROUND(100.0 * COUNT(DISTINCT a.account_id) FILTER (WHERE a.months_since_start = 9)  / c.cohort_size, 1) END AS month_9_pct,
       CASE WHEN c.months_observed >= 12 THEN ROUND(100.0 * COUNT(DISTINCT a.account_id) FILTER (WHERE a.months_since_start = 12) / c.cohort_size, 1) END AS month_12_pct
FROM cohorts c
LEFT JOIN activity a ON a.cohort_quarter = c.cohort_quarter
GROUP BY c.cohort_quarter, c.cohort_size, c.months_observed
ORDER BY c.cohort_quarter;
