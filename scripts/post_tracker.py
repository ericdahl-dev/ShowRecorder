#!/usr/bin/env python3
"""Facebook post tracker: the post log (docs/marketing/posts.csv) joined with showrecorder.app visits from PostHog.

Each posted link carries utm_source=facebook and its own utm_campaign. A person counts under the first
campaign link they arrived through in the last 60 days; their Join beta and App Store taps count if they
happen within a day of arriving. Eric's own visits are included.

Run under Doppler (POSTHOG_PERSONAL_API_KEY):
  doppler run -p ericdahl-dev -c prd -- python3 scripts/post_tracker.py            # print the table
  ... python3 scripts/post_tracker.py --json DIR       # also write posts/campaigns/daily.json for the tracker page
  ... python3 scripts/post_tracker.py --dashboard      # create or update the PostHog "Facebook posts" dashboard
"""
import argparse, csv, json, os, sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "..", "docs", "marketing", "posts.csv")
NUMBERS = ("members", "likes", "comments")
TZ = "America/New_York"
DASHBOARD = "Facebook posts"

# People per campaign: first arrival through a Facebook link, then what they did within a day.
LANDINGS = """SELECT person_id, properties.utm_campaign AS c, min(timestamp) AS t FROM events
WHERE properties.$host = 'showrecorder.app' AND properties.utm_source = 'facebook' AND properties.utm_campaign != ''
AND timestamp > now() - INTERVAL 60 DAY GROUP BY person_id, c"""
VISITS_SQL = f"""SELECT l.c AS campaign, count(DISTINCT l.person_id) AS people,
 countIf(e.event = '$pageview') AS pageviews, countIf(e.event = 'join_beta_clicked') AS join_beta,
 countIf(e.event = 'app_store_clicked' OR (e.event = 'mixer_page_cta_clicked' AND e.properties.destination = 'app_store')) AS app_store, toString(toTimeZone(max(e.timestamp), '{TZ}')) AS last_activity
FROM ({LANDINGS}) l LEFT JOIN events e ON e.person_id = l.person_id AND e.timestamp >= l.t
 AND e.timestamp < l.t + INTERVAL 1 DAY AND e.properties.$host = 'showrecorder.app'
GROUP BY campaign ORDER BY people DESC"""
DAILY_SQL = f"""SELECT c AS campaign, toString(toDate(toTimeZone(t, '{TZ}'))) AS day, count() AS people
FROM ({LANDINGS}) GROUP BY campaign, day ORDER BY day"""


def load_posts(path=LOG):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        for k, v in r.items():
            r[k] = None if v == "" else v
        for k in NUMBERS:
            if r.get(k) is not None:
                r[k] = int(r[k])
    return rows


def board(posts, visits):
    by = {v["campaign"]: v for v in visits}
    rows = []
    for p in posts:
        v = by.get(p["campaign"], {})
        rows.append({**p, **{k: v.get(k, 0) for k in ("people", "pageviews", "joinBeta", "appStore")},
                     "lastActivity": v.get("lastActivity")})
    logged = {p["campaign"] for p in posts}
    for v in visits:
        if v["campaign"] not in logged:
            rows.append({"campaign": v["campaign"], "kind": "Other", "group": v["campaign"], "status": "Not in the log",
                         "posted": None, "likes": None, "comments": None, "lastActivity": v.get("lastActivity"),
                         **{k: v[k] for k in ("people", "pageviews", "joinBeta", "appStore")}})
    return sorted(rows, key=lambda r: -r["people"])


def table(rows):
    cols = [("Where", "group", 40), ("Posted", "posted", 10), ("People", "people", 6), ("Beta", "joinBeta", 4),
            ("Store", "appStore", 5), ("Likes", "likes", 5), ("Cmts", "comments", 4), ("Status", "status", 30)]
    cell = lambda v: "-" if v is None else str(v)
    lines = ["  ".join(h.ljust(w) for h, _, w in cols)]
    for r in rows:
        lines.append("  ".join(cell(r.get(k))[:w].ljust(w) for _, k, w in cols))
    return "\n".join(lines)


def fetch(sql):
    visits = [{"campaign": c, "people": p, "pageviews": pv, "joinBeta": b, "appStore": s, "lastActivity": (last or "")[:16] or None}
              for c, p, pv, b, s, last in sql(VISITS_SQL)]
    daily = [{"campaign": c, "day": d, "people": n} for c, d, n in sql(DAILY_SQL)]
    return visits, daily


def _api(url, body=None, headers=None, method=None):
    import urllib.request
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def ensure_dashboard():
    """Create the PostHog dashboard and its two insights, or update them in place (matched by name)."""
    import weekly_numbers as wn
    headers = {"Authorization": "Bearer " + os.environ["POSTHOG_PERSONAL_API_KEY"]}
    projects = _api(f"{wn.POSTHOG}/api/projects/", headers=headers)["results"]
    base = f"{wn.POSTHOG}/api/projects/" + str(next(p["id"] for p in projects if p["name"] == wn.POSTHOG_PROJECT))
    dashes = _api(f"{base}/dashboards/?search={DASHBOARD.replace(' ', '%20')}", headers=headers)["results"]
    dash = next((d for d in dashes if d["name"] == DASHBOARD and not d.get("deleted")), None)
    if not dash:
        dash = _api(f"{base}/dashboards/", {"name": DASHBOARD,
            "description": "showrecorder.app visits from each Facebook post and ad (utm_source=facebook). Post log: docs/marketing/posts.csv."}, headers)
    tiles = [("Facebook posts: people and taps", VISITS_SQL), ("Facebook posts: new people per day", DAILY_SQL)]
    have = {t["insight"]["name"]: t["insight"]["id"] for t in dash.get("tiles", []) if t.get("insight")}
    for name, sql in tiles:
        body = {"name": name, "query": {"kind": "DataTableNode", "source": {"kind": "HogQLQuery", "query": sql}},
                "dashboards": [dash["id"]]}
        if name in have:
            _api(f"{base}/insights/{have[name]}/", body, headers, method="PATCH")
        else:
            _api(f"{base}/insights/", body, headers)
    return f"{wn.POSTHOG}/project/{base.rsplit('/', 1)[1]}/dashboard/{dash['id']}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", metavar="DIR", help="write posts.json, campaigns.json and daily.json here")
    ap.add_argument("--dashboard", action="store_true", help="create or update the PostHog dashboard")
    a = ap.parse_args()
    import weekly_numbers as wn
    posts = load_posts()
    visits, daily = fetch(wn.posthog)
    print(table(board(posts, visits)))
    if a.json:
        os.makedirs(a.json, exist_ok=True)
        for name, data in (("posts", posts), ("campaigns", visits), ("daily", daily)):
            with open(os.path.join(a.json, name + ".json"), "w") as f:
                json.dump(data, f, indent=1)
    if a.dashboard:
        print("dashboard:", ensure_dashboard())


if __name__ == "__main__":
    main()
