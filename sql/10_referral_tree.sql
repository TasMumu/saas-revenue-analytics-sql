-- 10. Referral trees: which customers brought in the most revenue, directly and down the chain?
-- Walks every referral chain from its first referrer, so an account referred by a referred account
-- still counts toward the original referrer.
-- Techniques: recursive CTE with depth and path tracking, cycle guard, FILTER aggregates

WITH RECURSIVE tree AS (
    -- anchor: referrers who were not themselves referred
    SELECT account_id AS root_id,
           account_id,
           0 AS depth,
           CAST(account_id AS text) AS path
    FROM accounts
    WHERE referred_by_account_id IS NULL
      AND account_id IN (SELECT referred_by_account_id FROM accounts)
    UNION ALL
    SELECT t.root_id,
           a.account_id,
           t.depth + 1,
           t.path || ' > ' || CAST(a.account_id AS text)
    FROM tree t
    JOIN accounts a ON a.referred_by_account_id = t.account_id
    WHERE t.depth < 10                                  -- guard against a bad loop in the data
),
current_mrr AS (
    SELECT account_id, monthly_price AS mrr
    FROM subscriptions
    WHERE valid_to IS NULL
),
tree_depth AS (
    SELECT root_id, MAX(depth) AS chain_depth
    FROM tree
    GROUP BY root_id
)
SELECT r.company_name                                         AS referrer,
       COUNT(*) FILTER (WHERE t.depth = 1)                    AS direct_referrals,
       COUNT(*) FILTER (WHERE t.depth > 1)                    AS indirect_referrals,
       d.chain_depth,
       COALESCE(SUM(m.mrr) FILTER (WHERE t.depth > 0), 0)     AS referred_mrr_today,
       MIN(t.path) FILTER (WHERE t.depth = d.chain_depth)     AS longest_chain    -- account ids, referrer first
FROM tree t
JOIN tree_depth d       ON d.root_id = t.root_id
JOIN accounts r         ON r.account_id = t.root_id
LEFT JOIN current_mrr m ON m.account_id = t.account_id
GROUP BY t.root_id, r.company_name, d.chain_depth
ORDER BY referred_mrr_today DESC, direct_referrals DESC
LIMIT 10;
