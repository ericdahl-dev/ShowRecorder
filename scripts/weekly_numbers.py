#!/usr/bin/env python3
"""Weekly numbers for ShowRecorder: the site, the App Store and app usage in one Markdown table, the last 7 days
next to the 7 before them and the total since launch (2026-10-28), with short notes (2x changes, the Nov 20
price-step check).

Run it under Doppler, which has the PostHog key and the Infisical machine identity; the App Store Connect key and
vendor number come from Infisical (project showrecorder, prod) unless they are already set:
  doppler run -p ericdahl-dev -c prd -- python3 scripts/weekly_numbers.py [out.md]
Environment: POSTHOG_PERSONAL_API_KEY; ASC_KEY_ID, ASC_ISSUER_ID, ASC_VENDOR_NUMBER and ASC_KEY_P8 (or ASC_KEY_PATH),
or INFISICAL_GER3_CLIENT_ID / _SECRET to fetch them. TODAY=YYYY-MM-DD reruns an earlier week. DAYS=1 makes
the daily email: yesterday beside the day before. Days are New York
days on the site and Apple's report days in the App Store. Never prints a secret.

Site: PostHog project "Owned Sites", $host = showrecorder.app. App Store: the daily sales reports (asc_stats.py).
App usage: take_started / take_stopped, sent only by TestFlight builds until 1.2 ships."""
import collections, dataclasses, datetime, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_stats

LAUNCH = datetime.date(2026, 10, 28)  # iOS 1.0 went live


@dataclasses.dataclass(frozen=True)
class Window:
    start: datetime.date
    end: datetime.date  # inclusive

    @property
    def days(self):
        return (self.end - self.start).days + 1

    @property
    def label(self):
        start, end = self.start, self.end
        if start == end:
            return start.strftime("%b %-d")
        tail = end.strftime("%-d") if end.month == start.month else end.strftime("%b %-d")
        return f"{start.strftime('%b %-d')}-{tail}"


def windows(today, days=7):
    """The last `days` full days (7 for the weekly email, 1 for the daily), the same span before them, and launch
    to yesterday."""
    end = today - datetime.timedelta(days=1)
    last = Window(end - datetime.timedelta(days=days - 1), end)
    prior = Window(last.start - datetime.timedelta(days=days), last.start - datetime.timedelta(days=1))
    return last, prior, Window(LAUNCH, end)


def span_names(window):
    """What the table and notes call the last and the prior window: by the day for the daily email, else by the
    week."""
    if window.days == 1:
        return "Yesterday", "Day before"
    return f"Last {window.days} days", f"Prior {window.days} days"


def change_flag(current, prior):
    """'2x up', '3.1x down', 'new' or 'to 0' when the last week moved 2x or more against the week before; else ''."""
    if current is None or prior is None or current == prior:
        return ""
    if prior == 0:
        return "new"
    if current == 0:
        return "to 0"
    ratio, way = (current / prior, "up") if current > prior else (prior / current, "down")
    return f"{ratio:.1f}".rstrip("0").rstrip(".") + f"x {way}" if ratio >= 2 else ""


SEARCH_ENGINES = ("google.", "bing.com", "duckduckgo.com", "search.yahoo.", "ecosia.org", "search.brave.com")


def source_of(utm_source, referring_domain):
    """Where a visitor came from: the utm_source when the link was tagged, else a name for the referrer."""
    named = (utm_source or "").strip()
    ref = (referring_domain or "").strip().lower()
    if "chatgpt" in named.lower() or "chatgpt.com" in ref:
        return "ChatGPT"
    if named.lower() == "facebook":  # tagged links say facebook; count them with Facebook referrers
        return "Facebook"
    if named:
        return named
    if ref == "facebook.com" or ref.endswith(".facebook.com"):
        return "Facebook"
    if any(engine in ref for engine in SEARCH_ENGINES):
        return "Search"
    if ref in ("", "$direct", "showrecorder.app"):
        return "Direct"
    return ref


def in_window(day, window):
    return window.start <= day <= window.end


def visitors_by_source(rows, window):
    """{source: visitors} from (day, visitor, utm_source, referring domain) rows; a visitor counts once, by their
    first row in the window."""
    first = {}
    for day, visitor, utm, ref in sorted(rows, key=lambda row: row[0]):
        if in_window(day, window) and visitor not in first:
            first[visitor] = source_of(utm, ref)
    return dict(collections.Counter(first.values()))


GUIDE_PREFIXES = ("/guides/", "/mixers/")  # the recording guides and the per-mixer pages


def guide_page_visitors(rows, window):
    """{path: unique visitors} for guide pages, from (day, path, visitor) rows."""
    seen = collections.defaultdict(set)
    for day, path, visitor in rows:
        if in_window(day, window) and path.startswith(GUIDE_PREFIXES):
            seen[path].add(visitor)
    return {path: len(visitors) for path, visitors in seen.items()}


def to_usd(proceeds, usd_rates):
    """({currency: amount}, {currency: units per dollar}) -> (dollars, {currency: amount with no rate})."""
    dollars, unconverted = 0.0, {}
    for currency, amount in proceeds.items():
        if usd_rates.get(currency):
            dollars += amount / usd_rates[currency]
        else:
            unconverted[currency] = amount
    return dollars, unconverted


def app_store_numbers(reports, window, app_id, sku, usd_rates):
    """The window's App Store numbers from {ISO day: daily sales report}."""
    days = {day: text for day, text in reports.items() if in_window(datetime.date.fromisoformat(day), window)}
    if not days:  # Apple hasn't published the window yet: "-", not 0, and no "to 0" flags
        return {key: None for key in ("downloads", "downloads_ios", "downloads_mac", "trials", "pro", "pro_codes",
                                      "packs", "proceeds_usd", "revenue_per_download", "download_to_pro")} | {
            "unconverted": {}, "report_days": []}
    summary = asc_stats.summarize(days, app_id, sku)
    dollars, unconverted = to_usd(summary.proceeds, usd_rates)
    downloads = summary.units["downloads"]
    return {
        "downloads": downloads,
        "downloads_ios": summary.downloads_by_platform["iOS"],
        "downloads_mac": summary.downloads_by_platform["Mac"],
        "trials": summary.units["trials"],
        "pro": summary.units["pro"],
        "pro_codes": summary.units["pro_codes"],
        "packs": summary.units["packs"],
        "proceeds_usd": dollars,
        "unconverted": unconverted,
        "revenue_per_download": dollars / downloads if downloads else None,
        "download_to_pro": summary.units["pro"] / downloads if downloads else None,
        "report_days": sorted(days),
    }


# App installs that aren't real users, by PostHog distinct_id (the app's install ID). A reinstall gets a new ID:
# add it here. Eric's iPhone 17 Pro (TestFlight, 2026-11-03 on) and a Santa Clara Mac on a non-TestFlight build
# that opened the app twice on 2026-11-05, most likely App Review.
INTERNAL_INSTALLS = frozenset({
    "3C50999B-5E8F-45B1-8390-31258B906369",  # Eric, iPhone
    "3E54B8D0-D782-42F8-8DBF-5DC06E4F7DB3",  # App Review Mac
})


def usage_numbers(rows, window):
    """Take events and the devices that sent them, from (day, event, device) rows, without internal installs."""
    events = [(event, device) for day, event, device in rows
              if in_window(day, window) and device not in INTERNAL_INSTALLS]
    counts = collections.Counter(event for event, _ in events)
    return {"take_started": counts["take_started"], "take_stopped": counts["take_stopped"],
            "devices": len({device for _, device in events})}


TOP_PAGES = 5


def show(value, kind):
    if value is None:
        return "-"
    return {"count": f"{value}", "usd": f"${value:,.2f}", "percent": f"{value:.1%}"}[kind]


def rows(sites, stores, usages):
    """The table's rows, in order: (label, [last, prior, since launch], kind), with section titles as (title, None,
    "section")."""
    out = []

    def section(title):
        out.append((title, None, "section"))

    def row(label, values, kind="count"):
        out.append((label, values, kind))

    section("Site (showrecorder.app)")
    row("Visitors", [s["visitors"] for s in sites])
    sources = collections.Counter(sites[2]["sources"])
    sources.setdefault("ChatGPT", 0)
    for source, _ in sorted(sources.items(), key=lambda item: (-item[1], item[0] == "ChatGPT", item[0])):
        row(f"from {source}", [s["sources"].get(source, 0) for s in sites])
    row("App Store clicks", [s["app_store_clicks"] for s in sites])
    top = sorted(sites[2]["pages"].items(), key=lambda item: (-item[1], item[0]))[:TOP_PAGES]
    for path, _ in top:
        row(f"`{path}`", [s["pages"].get(path, 0) for s in sites])

    section("App Store")
    row("Downloads, iPhone and iPad", [s["downloads_ios"] for s in stores])
    row("Downloads, Mac", [s["downloads_mac"] for s in stores])
    row("Trials started", [s["trials"] for s in stores])
    row("Pro sold", [s["pro"] for s in stores])
    row("Pro from offer codes", [s["pro_codes"] for s in stores])
    row("Packs sold", [s["packs"] for s in stores])
    row("Proceeds (USD)", [s["proceeds_usd"] for s in stores], "usd")
    row("Revenue per download", [s["revenue_per_download"] for s in stores], "usd")
    row("Download-to-Pro", [s["download_to_pro"] for s in stores], "percent")

    section("App usage (TestFlight only until 1.2 ships)")
    row("take_started", [u["take_started"] for u in usages])
    row("take_stopped", [u["take_stopped"] for u in usages])
    row("Devices recording", [u["devices"] for u in usages])
    return out


def table(windows, sites, stores, usages):
    """One Markdown table: a row per number, a column per window (last 7 days, prior 7, since launch), then the
    last week's 2x flag."""
    last, prior, launch = windows
    last_name, prior_name = span_names(last)
    lines = ["| | " + " | ".join([f"{last_name} ({last.label})", f"{prior_name} ({prior.label})",
                                  f"Since launch ({launch.label})"]) + " | Flag |",
             "|---|---:|---:|---:|---|"]
    for label, values, kind in rows(sites, stores, usages):
        if kind == "section":
            lines.append(f"| **{label}** | | | | |")
        else:
            cells = " | ".join(show(v, kind) for v in values)
            lines.append(f"| {label} | {cells} | {change_flag(values[0], values[1])} |")
    return "\n".join(lines) + "\n"


PRICE_STEP_FLOOR = 0.055  # at $9.99 (about $8.49 net), the download-to-Pro that matches $0.47 per download at $4.99


def notes(windows, sites, stores, usages):
    """Short flags under the table: 2x changes, the Nov 20 price-step check, and what the data leaves out."""
    last = windows[0]
    last_name, prior_name = span_names(last)
    out = []
    flags = [f"{label} {change_flag(values[0], values[1])}" for label, values, kind in rows(sites, stores, usages)
             if kind != "section" and change_flag(values[0], values[1])]
    out.append(f"2x or more against the {prior_name.lower()}: " + ("; ".join(flags) if flags else "none") + ".")

    def check(name, store):
        rate = store["download_to_pro"]
        if store["downloads"] is None:
            return f"{name} - (no report yet)"
        if rate is None:
            return f"{name} - (no downloads)"
        return f"{name} {rate:.1%} ({'holds' if rate >= PRICE_STEP_FLOOR - 1e-9 else 'below'})"

    out.append(f"Nov 20 price step check: at $9.99, download-to-Pro must stay at or above {PRICE_STEP_FLOOR:.1%} "
               f"to match revenue per download at $4.99. Now: {check(last_name.lower(), stores[0])}, "
               f"{check('since launch', stores[2])}.")
    out.append("App usage events (take_started, take_stopped) come only from TestFlight builds until 1.2 ships "
               "to the App Store.")
    prior = windows[1]
    if prior.start < LAUNCH:
        early = (min(LAUNCH, prior.end + datetime.timedelta(days=1)) - prior.start).days
        out.append(f"{prior_name} include {early} days before launch ({LAUNCH.strftime('%b %-d')}), so their App "
                   "Store numbers cover fewer days.")
    days = stores[0]["report_days"]
    if not days:
        out.append(f"No App Store reports for {last_name.lower()} yet.")
    elif days[-1] < last.end.isoformat():
        through = datetime.date.fromisoformat(days[-1])
        out.append(f"App Store reports run through {through.strftime('%b %-d')}; Apple publishes a day's report the "
                   "next day.")
    unconverted = stores[2]["unconverted"]
    if unconverted:
        listed = ", ".join(f"{c} {v:,.2f}" for c, v in sorted(unconverted.items()))
        out.append(f"Proceeds with no exchange rate, left out of USD since launch: {listed}.")
    return out


def report(today, sites, stores, usages, days=7):
    windows_ = windows(today, days)
    kind = "daily" if days == 1 else "weekly"
    body = [f"# ShowRecorder {kind} numbers, {today.isoformat()}", "", table(windows_, sites, stores, usages), "Notes:", ""]
    body += [f"- {note}" for note in notes(windows_, sites, stores, usages)]
    return "\n".join(body) + "\n"


# Everything below talks to the network; the tests stop above this line.

POSTHOG = "https://us.posthog.com"
POSTHOG_PROJECT = "Owned Sites"
SITE = "showrecorder.app"
TIME_ZONE = "America/New_York"
# A tap on an App Store button: the badge, or a mixer page's button, which sends destination 'app_store'
# (not a URL); the same count as post_tracker.py.
APP_STORE_CLICK = ("(event = 'app_store_clicked' OR (event = 'mixer_page_cta_clicked' "
                   "AND toString(properties.destination) = 'app_store'))")
INFISICAL = "https://infisical.ericdahl.dev/api"
INFISICAL_PROJECT = "23bfbf90-439d-4edf-a7d6-9bab28b43971"  # showrecorder
ASC_SECRETS = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "ASC_VENDOR_NUMBER")
RATES = "https://open.er-api.com/v6/latest/USD"  # free, no key: {"rates": {"EUR": 0.86, ...}} per dollar


def http_json(url, body=None, headers=None):
    import json, urllib.request
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def load_asc_secrets():
    """Fills the App Store Connect variables from Infisical (project showrecorder, prod) when they aren't set, with
    the machine identity from Doppler (INFISICAL_GER3_CLIENT_ID / _SECRET). Values never leave the environment."""
    missing = [name for name in ASC_SECRETS if not os.environ.get(name)]
    if not missing or (os.environ.get("ASC_KEY_PATH") and missing == ["ASC_KEY_P8"]):
        return
    login = http_json(f"{INFISICAL}/v1/auth/universal-auth/login", {
        "clientId": os.environ["INFISICAL_GER3_CLIENT_ID"], "clientSecret": os.environ["INFISICAL_GER3_CLIENT_SECRET"]})
    auth = {"Authorization": "Bearer " + login["accessToken"]}
    for name in missing:
        url = f"{INFISICAL}/v3/secrets/raw/{name}?workspaceId={INFISICAL_PROJECT}&environment=prod"
        os.environ[name] = http_json(url, headers=auth)["secret"]["secretValue"]


def usd_rates():
    try:
        return http_json(RATES)["rates"]
    except Exception as error:  # the report still runs; proceeds outside USD are listed apart
        print(f"No exchange rates ({error}); only USD proceeds are converted.", file=sys.stderr)
        return {"USD": 1}


def posthog(sql):
    headers = {"Authorization": "Bearer " + os.environ["POSTHOG_PERSONAL_API_KEY"]}
    projects = http_json(f"{POSTHOG}/api/projects/", headers=headers)["results"]
    project = next(p["id"] for p in projects if p["name"] == POSTHOG_PROJECT)
    return http_json(f"{POSTHOG}/api/projects/{project}/query/", {"query": {"kind": "HogQLQuery", "query": sql}},
                     headers)["results"]


def fetch_posthog(start, end):
    day = f"toDate(toTimeZone(timestamp, '{TIME_ZONE}'))"
    span = f"{day} >= toDate('{start}') AND {day} <= toDate('{end}')"
    site = f"properties.$host = '{SITE}' AND {span}"

    def rows(sql):
        return [(datetime.date.fromisoformat(r[0]), *r[1:]) for r in posthog(sql + " LIMIT 50000")]

    visitors = rows(f"SELECT toString({day}) d, toString(person_id), argMin(properties.utm_source, timestamp), "
                    f"argMin(properties.$referring_domain, timestamp) FROM events "
                    f"WHERE event = '$pageview' AND {site} GROUP BY d, person_id")
    pages = rows(f"SELECT DISTINCT toString({day}), properties.$pathname, toString(person_id) FROM events "
                 f"WHERE event = '$pageview' AND {site} AND "
                 f"(properties.$pathname LIKE '/guides/%' OR properties.$pathname LIKE '/mixers/%')")
    clicks = rows(f"SELECT toString({day}), toString(uuid) FROM events WHERE {site} AND {APP_STORE_CLICK}")
    takes = rows(f"SELECT toString({day}), event, distinct_id FROM events "
                 f"WHERE event IN ('take_started', 'take_stopped') AND properties.app = 'showrecorder' AND {span}")
    return visitors, pages, clicks, takes


def fetch_sales_reports(start, end):
    reports, day = {}, start
    while day <= end:
        text = asc_stats.sales_report(day.isoformat())
        if text is not None:
            reports[day.isoformat()] = text
        day += datetime.timedelta(days=1)
    return reports


def main():
    today = datetime.date.fromisoformat(os.environ["TODAY"]) if os.environ.get("TODAY") else datetime.date.today()
    days = int(os.environ.get("DAYS", "7"))
    last, prior, launch = windows(today, days)
    start = min(prior.start, launch.start)
    visitors, pages, clicks, takes = fetch_posthog(start, last.end)
    load_asc_secrets()
    with asc_stats.asc_key():
        app_id, sku = asc_stats.app_ids()
        reports = fetch_sales_reports(start, last.end)
    rates = usd_rates()
    sites, stores, usages = [], [], []
    for window in (last, prior, launch):
        sources = visitors_by_source(visitors, window)
        sites.append({"visitors": sum(sources.values()), "sources": sources,
                      "pages": guide_page_visitors(pages, window),
                      "app_store_clicks": sum(1 for day, _ in clicks if in_window(day, window))})
        stores.append(app_store_numbers(reports, window, app_id, sku, rates))
        usages.append(usage_numbers(takes, window))
    text = report(today, sites, stores, usages, days)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as out:
            out.write(text)
    print(text, end="")


if __name__ == "__main__":
    main()
