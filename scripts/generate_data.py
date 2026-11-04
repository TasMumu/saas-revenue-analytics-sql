"""Generate the synthetic data for the SaaS revenue analytics project.

Fernhollow Software is a fictional B2B SaaS company. Every account, user, event and ticket
here is invented. The simulation is seeded, so running this script always writes the
same CSV files.

    python scripts/generate_data.py
"""
import csv
import random
from datetime import date, datetime, timedelta
from pathlib import Path

random.seed(20250630)
OUT = Path(__file__).resolve().parent.parent / 'data'
OUT.mkdir(exist_ok=True)

START, END = date(2023, 1, 1), date(2025, 6, 30)
PLANS = {'Starter': 15, 'Growth': 32, 'Scale': 55}          # list price per seat per month
PLAN_ORDER = ['Starter', 'Growth', 'Scale']
SEATS = {'Starter': (2, 10), 'Growth': (5, 25), 'Scale': (15, 60)}
REGIONS = [('North America', .38), ('Europe', .30), ('APAC', .20), ('LATAM', .12)]
CHURN = {'North America': .020, 'Europe': .022, 'APAC': .030, 'LATAM': .036}
CHANNELS = [('Organic search', .30), ('Paid search', .22), ('Referral', .18), ('Partner', .14), ('Outbound', .16)]
CONVERT = {'Organic search': .40, 'Paid search': .30, 'Referral': .55, 'Partner': .50, 'Outbound': .35}
INDUSTRIES = ['Retail', 'Healthcare', 'Logistics', 'Financial services', 'Education', 'Manufacturing', 'Media', 'Hospitality']
ADJ = ['Amber', 'Birch', 'Cobalt', 'Driftwood', 'Ember', 'Fallow', 'Granite', 'Harbor', 'Indigo', 'Juniper', 'Kestrel', 'Lantern',
       'Meadow', 'Nimbus', 'Orchard', 'Pebble', 'Quarry', 'Russet', 'Saffron', 'Thistle', 'Umber', 'Vale', 'Willow', 'Yarrow']
NOUN = ['Ridge', 'Brook', 'Field', 'Hollow', 'Crest', 'Point', 'Grove', 'Bay', 'Stone', 'Gate', 'Mill', 'Reach']
SUFFIX = ['Logistics', 'Health', 'Retail Co', 'Partners', 'Studios', 'Foods', 'Supply', 'Learning', 'Finance', 'Works', 'Labs', 'Group']
EVENTS = [('report_created', .35), ('dashboard_viewed', .30), ('export', .12), ('dashboard_shared', .10), ('invite_sent', .05), ('integration_connected', .03)]
PRIORITY = {'urgent': (.07, .6), 'high': (.18, 2.5), 'normal': (.45, 5.0), 'low': (.30, 14.0)}   # share, median first-response hours


def pick(pairs):
    return random.choices([p for p, _ in pairs], [w for _, w in pairs])[0]


def rand_date(a, b):
    return a + timedelta(days=random.randint(0, (b - a).days))


def at(d, hour_lo=8, hour_hi=18):
    return datetime(d.year, d.month, d.day, random.randint(hour_lo, hour_hi), random.randint(0, 59), random.randint(0, 59))


# Accounts --------------------------------------------------------------------------------
names, accounts = set(), []
for i in range(1, 601):
    while True:
        n = f'{random.choice(ADJ)} {random.choice(NOUN)} {random.choice(SUFFIX)}'
        if n not in names:
            names.add(n)
            break
    accounts.append(dict(account_id=i, company_name=n, signup_date=rand_date(START, date(2025, 5, 31)),
                         region=pick(REGIONS), industry=random.choice(INDUSTRIES), acquisition_channel=pick(CHANNELS)))
accounts.sort(key=lambda a: a['signup_date'])
for i, a in enumerate(accounts, 1):          # ids follow signup order, so referrers always signed up earlier
    a['account_id'] = i
for a in accounts:
    earlier = [b for b in accounts if b['signup_date'] < a['signup_date'] - timedelta(days=14)]
    a['referred_by_account_id'] = random.choice(earlier[-250:])['account_id'] if a['acquisition_channel'] == 'Referral' and earlier else None

# Subscriptions: one row per plan/seat state, valid_from inclusive, valid_to exclusive -------
subs, sub_id, paid_periods = [], 0, {}


def open_row(acc, plan, seats, start):
    global sub_id
    sub_id += 1
    row = dict(subscription_id=sub_id, account_id=acc['account_id'], plan=plan, seats=seats,
               monthly_price=round(seats * PLANS[plan], 2), valid_from=start, valid_to=None)
    subs.append(row)
    return row


for a in accounts:
    a['converted'] = random.random() < CONVERT[a['acquisition_channel']]
    a['activated_day'] = None
    if a['converted']:
        a['activated_day'] = random.randint(0, 6) if random.random() < .85 else random.randint(8, 20)
        late = random.random() < .15
        start = a['signup_date'] + timedelta(days=random.randint(31, 60) if late else random.randint(3, 30))
        if start > END:
            a['converted'] = False
            continue
        plan = random.choices(PLAN_ORDER, [.55, .33, .12])[0]
        row = open_row(a, plan, random.randint(*SEATS[plan]), start)
        periods, period_start, d = [], start, start
        while True:
            d += timedelta(days=random.randint(25, 35))
            if d > END:
                break
            r = random.random()
            churn = CHURN[a['region']] * (1.3 if row['plan'] == 'Starter' else .8)
            if r < churn:                                            # churn, maybe come back later
                row['valid_to'] = d
                periods.append((period_start, d))
                if random.random() < .2:
                    back = d + timedelta(days=random.randint(60, 180))
                    if back <= END:
                        row = open_row(a, 'Starter', random.randint(*SEATS['Starter']), back)
                        period_start, d = back, back
                        continue
                row = None
                break
            elif r < churn + .02 and row['plan'] != 'Scale':          # plan upgrade
                new_plan = PLAN_ORDER[PLAN_ORDER.index(row['plan']) + 1]
                row['valid_to'] = d
                row = open_row(a, new_plan, max(row['seats'], SEATS[new_plan][0]), d)
            elif r < churn + .08:                                     # seat expansion
                row['valid_to'] = d
                row = open_row(a, row['plan'], row['seats'] + max(1, round(row['seats'] * random.uniform(.1, .3))), d)
            elif r < churn + .11 and row['seats'] > 2:                # seat contraction
                row['valid_to'] = d
                row = open_row(a, row['plan'], max(1, row['seats'] - max(1, round(row['seats'] * random.uniform(.1, .3)))), d)
            elif r < churn + .118 and row['plan'] != 'Starter':      # plan downgrade
                new_plan = PLAN_ORDER[PLAN_ORDER.index(row['plan']) - 1]
                row['valid_to'] = d
                row = open_row(a, new_plan, row['seats'], d)
        if row is not None:
            periods.append((period_start, END + timedelta(days=1)))
        paid_periods[a['account_id']] = periods
    elif random.random() < .35:
        a['activated_day'] = random.randint(0, 6)

# Users and product events ------------------------------------------------------------------
users, events = [], []
for a in accounts:
    n_users = random.randint(1, 6) if a['converted'] else random.randint(1, 2)
    first_user = None
    for _ in range(n_users):
        uid = len(users) + 1
        created = a['signup_date'] + timedelta(days=0 if first_user is None else random.randint(0, 20))
        users.append(dict(user_id=uid, account_id=a['account_id'], created_at=at(created, 7, 19)))
        first_user = first_user or uid
        periods = paid_periods.get(a['account_id'], [])
        trial_end = a['signup_date'] + timedelta(days=30)
        last = max([p[1] for p in periods] + [trial_end])
        d = created
        while d < min(last, END + timedelta(days=1)):
            paid_now = any(s <= d < e for s, e in periods)
            in_trial = d < trial_end
            p = (.06 if d.weekday() < 5 else .02) if paid_now else (.12 if in_trial else 0)
            if random.random() < p:
                t = at(d)
                for s in range(1 if random.random() < .8 else 2):
                    events.append([uid, t, 'login'])
                    for _ in range(random.randint(1, 7)):
                        t += timedelta(minutes=random.randint(1, 12), seconds=random.randint(0, 59))
                        name = pick(EVENTS)
                        if name == 'integration_connected' and (d - a['signup_date']).days <= 7:
                            name = 'dashboard_viewed'     # integrations in the first week only come from onboarding below
                        events.append([uid, t, name])
                    t += timedelta(minutes=random.randint(90, 240))
            d += timedelta(days=1)
    if a['activated_day'] is not None:                            # onboarding session by the first user
        t = at(a['signup_date'] + timedelta(days=a['activated_day']))
        if t.date() <= END:
            for name in ['login', 'integration_connected', 'report_created']:
                events.append([first_user, t, name])
                t += timedelta(minutes=random.randint(2, 9))

events.sort(key=lambda e: (e[1], e[0]))
raw = [[i + 1] + e for i, e in enumerate(events)]
dupes = random.sample(raw, k=round(len(raw) * .015))              # late-arriving duplicate loads
raw += [[len(raw) + i + 1] + d[1:] for i, d in enumerate(sorted(dupes, key=lambda r: r[2]))]

# Support tickets ---------------------------------------------------------------------------
tickets = []
for acc_id, periods in paid_periods.items():
    for s, e in periods:
        months = max(1, (min(e, END) - s).days / 30)
        for _ in range(sum(random.random() < .3 for _ in range(round(months)))):
            opened = at(rand_date(s, min(e, END)), 0, 23)
            pr = random.choices(list(PRIORITY), [v[0] for v in PRIORITY.values()])[0]
            fr = opened + timedelta(hours=PRIORITY[pr][1] * random.lognormvariate(0, .8))
            res = fr + timedelta(hours=20 * random.lognormvariate(0, .9))
            end_ts = datetime(2025, 6, 30, 23, 59, 59)
            tickets.append(dict(ticket_id=0, account_id=acc_id, priority=pr, opened_at=opened,
                                first_response_at=fr if fr <= end_ts else None, resolved_at=res if res <= end_ts else None))
tickets.sort(key=lambda t: t['opened_at'])
for i, t in enumerate(tickets, 1):
    t['ticket_id'] = i


# Write -------------------------------------------------------------------------------------
def write(name, header, rows):
    with open(OUT / f'{name}.csv', 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows:
            w.writerow(['' if v is None else v.strftime('%Y-%m-%d %H:%M:%S') if isinstance(v, datetime) else v for v in r])
    print(f'{name}: {len(rows):,} rows')


write('accounts', ['account_id', 'company_name', 'signup_date', 'region', 'industry', 'acquisition_channel', 'referred_by_account_id'],
      [[a[k] for k in ['account_id', 'company_name', 'signup_date', 'region', 'industry', 'acquisition_channel', 'referred_by_account_id']] for a in accounts])
write('subscriptions', ['subscription_id', 'account_id', 'plan', 'seats', 'monthly_price', 'valid_from', 'valid_to'],
      [[s[k] for k in ['subscription_id', 'account_id', 'plan', 'seats', 'monthly_price', 'valid_from', 'valid_to']] for s in subs])
write('users', ['user_id', 'account_id', 'created_at'], [[u['user_id'], u['account_id'], u['created_at']] for u in users])
write('events_raw', ['event_id', 'user_id', 'event_time', 'event_name'], raw)
write('support_tickets', ['ticket_id', 'account_id', 'priority', 'opened_at', 'first_response_at', 'resolved_at'],
      [[t[k] for k in ['ticket_id', 'account_id', 'priority', 'opened_at', 'first_response_at', 'resolved_at']] for t in tickets])
