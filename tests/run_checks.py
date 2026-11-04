"""Run every query on DuckDB, save each result to results/, and check that the numbers agree.

The SQL is written for PostgreSQL; DuckDB runs the same files, which makes the checks
easy to repeat without a database server:

    pip install duckdb
    python tests/run_checks.py
"""
import csv
import sys
from decimal import Decimal
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
SQL, DATA, RESULTS = ROOT / 'sql', ROOT / 'data', ROOT / 'results'
RESULTS.mkdir(exist_ok=True)

con = duckdb.connect()
con.execute((SQL / '00_schema.sql').read_text(encoding='utf-8'))
for table in ['accounts', 'subscriptions', 'users', 'events_raw', 'support_tickets']:
    con.execute(f"COPY {table} FROM '{(DATA / f'{table}.csv').as_posix()}' (HEADER)")

out = {}
for f in sorted(SQL.glob('[0-9][0-9]_*.sql')):
    if f.name.startswith('00'):
        continue
    cur = con.execute(f.read_text(encoding='utf-8'))
    cols = [d[0] for d in cur.description]
    rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    out[f.stem] = rows
    with open(RESULTS / f'{f.stem}.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        w.writerows([[r[c] for c in cols] for r in rows])
    print(f'{f.stem}: {len(rows)} rows')

failures = []


def check(ok, msg):
    print(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        failures.append(msg)


D = lambda x: Decimal(str(x))

# 1. The clean view drops exactly the duplicate deliveries
dup = next(r for r in out['01_duplicate_events'] if r['event_name'] == 'All events')
clean = con.execute('SELECT COUNT(*) FROM events').fetchone()[0]
check(dup['clean_events'] == clean and dup['raw_events'] - dup['duplicate_deliveries'] == clean,
      f"events view holds {clean:,} rows = raw {dup['raw_events']:,} - duplicates {dup['duplicate_deliveries']:,}")

# 2-3. MRR bridge reconciles, chains month to month, and matches the MRR series
mrr = {r['month']: D(r['mrr']) for r in out['02_monthly_mrr']}
bridge = out['03_mrr_bridge']
ok_sum = all(D(r['opening_mrr']) + D(r['new_mrr']) + D(r['reactivation_mrr']) + D(r['expansion_mrr'])
             + D(r['contraction_mrr']) + D(r['churned_mrr']) == D(r['closing_mrr']) for r in bridge)
check(ok_sum, 'every month: opening + new + reactivation + expansion + contraction + churn = closing')
check(all(D(a['closing_mrr']) == D(b['opening_mrr']) for a, b in zip(bridge, bridge[1:])), "each month's closing MRR = next month's opening MRR")
check(all(D(r['closing_mrr']) == mrr[r['month']] for r in bridge), 'bridge closing MRR = monthly MRR series (query 2) in all 30 months')

# 4. Cohorts cover every account that ever paid
paying = con.execute('SELECT COUNT(DISTINCT account_id) FROM subscriptions').fetchone()[0]
check(sum(r['cohort_size'] for r in out['04_cohort_retention']) == paying, f'cohort sizes add up to all {paying} accounts that ever paid')

# 5. NRR base = MRR on 30 June 2024
base = next(r for r in out['05_net_revenue_retention'] if r['region'] == 'All regions')
june24 = next(v for k, v in mrr.items() if str(k) == '2024-06-01')
check(D(base['base_mrr']) == june24, f"NRR base MRR {base['base_mrr']} = June 2024 MRR from query 2")
check(D(base['grr_pct']) <= D(base['nrr_pct']), 'gross retention is never above net retention')

# 6. Funnel counts every signup
allch = next(r for r in out['06_signup_funnel'] if r['channel'] == 'All channels')
check(allch['signups'] == 600, 'funnel covers all 600 signups')

# 9. Rolling actives are nested
check(all(r['dau'] <= r['wau'] <= r['mau'] for r in out['09_rolling_active_users']), 'DAU <= WAU <= MAU on every day')

# 11. Revenue mix subtotals agree with the grand total and with June 2025 MRR
mix = out['11_revenue_mix']
total = next(r for r in mix if r['region'] == 'All regions' and r['plan'] == 'All plans')
june25 = next(v for k, v in mrr.items() if str(k) == '2025-06-01')
check(D(total['mrr']) == june25, f"revenue mix total {total['mrr']} = June 2025 MRR from query 2")
regions = [r for r in mix if r['region'] != 'All regions' and r['plan'] == 'All plans']
plans = [r for r in mix if r['region'] == 'All regions' and r['plan'] != 'All plans']
check(sum(D(r['mrr']) for r in regions) == D(total['mrr']) == sum(D(r['mrr']) for r in plans), 'region subtotals and plan subtotals both add up to the total')

# 12. Every ticket is in exactly one priority row
check(sum(r['tickets'] for r in out['12_support_sla']) == con.execute('SELECT COUNT(*) FROM support_tickets').fetchone()[0], 'SLA rows cover every ticket')

print('\nAll checks passed' if not failures else f'\n{len(failures)} check(s) failed')
sys.exit(1 if failures else 0)
