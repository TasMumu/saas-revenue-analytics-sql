-- 5. Net and gross revenue retention over the last 12 months, by region
-- Base: every account paying on 30 June 2024. Retained: what those same accounts pay on 30 June 2025.
-- NRR counts expansion; GRR caps each account at its base MRR, so it only shows losses.
-- Techniques: point-in-time snapshots with FILTER, LEAST, ROLLUP for the all-regions row

WITH snapshots AS (
    SELECT account_id,
           SUM(monthly_price) FILTER (WHERE valid_from <= DATE '2024-06-30'
                                        AND (valid_to IS NULL OR valid_to > DATE '2024-06-30')) AS base_mrr,
           SUM(monthly_price) FILTER (WHERE valid_from <= DATE '2025-06-30'
                                        AND (valid_to IS NULL OR valid_to > DATE '2025-06-30')) AS current_mrr
    FROM subscriptions
    GROUP BY account_id
)
SELECT CASE WHEN GROUPING(a.region) = 1 THEN 'All regions' ELSE a.region END                    AS region,
       COUNT(*)                                                                                AS base_accounts,
       SUM(s.base_mrr)                                                                         AS base_mrr,
       SUM(COALESCE(s.current_mrr, 0))                                                         AS retained_mrr,
       ROUND(100.0 * SUM(COALESCE(s.current_mrr, 0)) / SUM(s.base_mrr), 1)                     AS nrr_pct,
       ROUND(100.0 * SUM(LEAST(COALESCE(s.current_mrr, 0), s.base_mrr)) / SUM(s.base_mrr), 1)  AS grr_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.current_mrr IS NULL) / COUNT(*), 1)              AS logo_churn_pct
FROM snapshots s
JOIN accounts a ON a.account_id = s.account_id
WHERE s.base_mrr IS NOT NULL
GROUP BY ROLLUP (a.region)
ORDER BY GROUPING(a.region), nrr_pct DESC;
