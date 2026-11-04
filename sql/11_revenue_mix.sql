-- 11. Current revenue mix by region and plan, with every subtotal in one query
-- Techniques: GROUPING SETS, GROUPING() to label subtotal rows, scalar subquery for share of total

SELECT CASE WHEN GROUPING(a.region) = 1 THEN 'All regions' ELSE a.region END AS region,
       CASE WHEN GROUPING(s.plan)   = 1 THEN 'All plans'   ELSE s.plan   END AS plan,
       COUNT(*)                                                             AS accounts,
       SUM(s.seats)                                                         AS seats,
       SUM(s.monthly_price)                                                 AS mrr,
       ROUND(SUM(s.monthly_price) / COUNT(*), 2)                            AS arpa,
       ROUND(100.0 * SUM(s.monthly_price)
             / (SELECT SUM(monthly_price) FROM subscriptions WHERE valid_to IS NULL), 1) AS share_of_mrr_pct
FROM subscriptions s
JOIN accounts a ON a.account_id = s.account_id
WHERE s.valid_to IS NULL
GROUP BY GROUPING SETS ((a.region, s.plan), (a.region), (s.plan), ())
ORDER BY GROUPING(a.region), a.region, GROUPING(s.plan),
         CASE s.plan WHEN 'Starter' THEN 1 WHEN 'Growth' THEN 2 WHEN 'Scale' THEN 3 END;
