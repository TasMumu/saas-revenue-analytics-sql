-- 1. Data quality: duplicate event deliveries
-- How many raw events are repeat deliveries of the same (user, time, event), by event type?
-- Techniques: ROW_NUMBER over a natural key, FILTER aggregates, GROUPING SETS for a total row

WITH ranked AS (
    SELECT event_name,
           ROW_NUMBER() OVER (PARTITION BY user_id, event_time, event_name ORDER BY event_id) AS delivery_no
    FROM events_raw
)
SELECT COALESCE(event_name, 'All events')                                     AS event_name,
       COUNT(*)                                                               AS raw_events,
       COUNT(*) FILTER (WHERE delivery_no > 1)                                AS duplicate_deliveries,
       COUNT(*) FILTER (WHERE delivery_no = 1)                                AS clean_events,
       ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_no > 1) / COUNT(*), 2)   AS duplicate_pct
FROM ranked
GROUP BY GROUPING SETS ((event_name), ())
ORDER BY GROUPING(event_name), raw_events DESC;
