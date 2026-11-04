-- Build the schema, load the CSVs and run all 13 analyses on PostgreSQL.
-- Usage, from the repository folder:
--   createdb fernhollow
--   psql -d fernhollow -f run_all.sql

\set ON_ERROR_STOP on
\i sql/00_schema.sql

\copy accounts        FROM 'data/accounts.csv'        WITH (FORMAT csv, HEADER true)
\copy subscriptions   FROM 'data/subscriptions.csv'   WITH (FORMAT csv, HEADER true)
\copy users           FROM 'data/users.csv'           WITH (FORMAT csv, HEADER true)
\copy events_raw      FROM 'data/events_raw.csv'      WITH (FORMAT csv, HEADER true)
\copy support_tickets FROM 'data/support_tickets.csv' WITH (FORMAT csv, HEADER true)
ANALYZE;

\echo '1. Duplicate event deliveries'
\i sql/01_duplicate_events.sql
\echo '2. Monthly recurring revenue'
\i sql/02_monthly_mrr.sql
\echo '3. MRR bridge'
\i sql/03_mrr_bridge.sql
\echo '4. Logo retention by cohort'
\i sql/04_cohort_retention.sql
\echo '5. Net and gross revenue retention'
\i sql/05_net_revenue_retention.sql
\echo '6. Signup funnel'
\i sql/06_signup_funnel.sql
\echo '7. Sessions by plan'
\i sql/07_sessions_by_plan.sql
\echo '8. Longest weekly activity streaks'
\i sql/08_weekly_streaks.sql
\echo '9. Rolling active users'
\i sql/09_rolling_active_users.sql
\echo '10. Referral trees'
\i sql/10_referral_tree.sql
\echo '11. Revenue mix'
\i sql/11_revenue_mix.sql
\echo '12. Support SLA'
\i sql/12_support_sla.sql
\echo '13. Churn-risk watchlist'
\i sql/13_churn_risk.sql
