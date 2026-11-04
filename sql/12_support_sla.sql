-- 12. Support response times against SLA targets, by priority
-- Targets for the first response: urgent 1 hour, high 4, normal 8, low 24.
-- A ticket still waiting at the end of the data (30 June 2025) counts by how long it has waited so far.
-- Techniques: interval arithmetic, percentile_cont, FILTER, COALESCE for open tickets

WITH tickets AS (
    SELECT priority,
           CASE priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 4 WHEN 'normal' THEN 8 ELSE 24 END AS target_hours,
           EXTRACT(EPOCH FROM (COALESCE(first_response_at, TIMESTAMP '2025-06-30 23:59:59') - opened_at)) / 3600.0 AS wait_hours,
           EXTRACT(EPOCH FROM (resolved_at - opened_at)) / 3600.0 AS resolution_hours,
           first_response_at IS NULL AS awaiting_response
    FROM support_tickets
)
SELECT priority,
       target_hours,
       COUNT(*)                                                                               AS tickets,
       ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY wait_hours) AS numeric), 2)       AS median_first_response_h,
       ROUND(CAST(percentile_cont(0.9) WITHIN GROUP (ORDER BY wait_hours) AS numeric), 2)       AS p90_first_response_h,
       ROUND(100.0 * COUNT(*) FILTER (WHERE wait_hours > target_hours) / COUNT(*), 1)         AS sla_breach_pct,
       ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY resolution_hours) AS numeric), 1) AS median_resolution_h,
       COUNT(*) FILTER (WHERE awaiting_response)                                              AS awaiting_response
FROM tickets
GROUP BY priority, target_hours
ORDER BY target_hours;
