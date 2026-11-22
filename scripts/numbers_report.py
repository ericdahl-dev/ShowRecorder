#!/usr/bin/env python3
"""The ShowRecorder numbers report: two weeks of the site, Facebook ads, App Store sales, TestFlight, tester usage,
errors and support on one HTML page.

  doppler run -p ericdahl-dev -c prd -- python3 scripts/numbers_report.py collect   # writes numbers.json
  python3 scripts/numbers_report.py render                                          # writes showrecorder-numbers.html

Both work in one folder outside the repo, NUMBERS_DIR (default ~/.cache/showrecorder-numbers), because the data
holds testers' feedback. `collect` reads PostHog, App Store Connect and Chatwoot (read only) with the same queries and helpers as
weekly_numbers.py, so the page, the weekly table and the daily email agree. The rest is written by hand into the
folder before `render`, since no script can reach it:
  ads.json        Facebook Ads Manager: {"read_at", "range", "start", "budget", "ads": [{"name", "tag", "spent",
                  "impressions", "reach", "clicks", "ends"}], "notices": [...]}
  glitchtip.json  {"read_at", "app": [{"title", "count"}], "web": [{"title", "count", "note"}]}
  notes.json      {"needs_you": [{"tag", "level", "text"}], "feedback_notes": {"<feedback date>": "..."},
                  "sections": [{"title", "src", "points": [...]}], "price_check": {"label", "needs"}}
A missing file leaves its part out. MINE (comma-separated) is Eric's TestFlight addresses: his own feedback is
counted, not listed. Environment for `collect` as in weekly_numbers.py. Never prints a secret.
"""
import collections, datetime, html, json, os, sys

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weekly_numbers as wn

DAYS = 14
TIME_ZONE = "America/New_York"
DIR = os.environ.get("NUMBERS_DIR") or os.path.expanduser("~/.cache/showrecorder-numbers")
USAGE_NAMES = {
    "app_opened": "Opened the app", "show_created": "Created a Show", "take_started": "Started a Take",
    "take_stopped": "Stopped a Take", "mixer_link_connected": "Connected Mixer Link", "drive_connected": "Connected a Drive",
    "trial_started": "Started a trial", "show_deleted": "Deleted a Show",
}


# ---- Collect: turning query rows into the report's numbers. No network above the marker further down.

def site_days(rows, days):
    """[{day, visitors, facebook}] for each day, from (day, visitor, utm_source, utm_campaign, referring domain)
    rows, one per visitor and day. Facebook means a tagged facebook link or a Facebook referrer (wn.source_of)."""
    by_day = collections.defaultdict(dict)
    for day, visitor, utm, _campaign, ref in rows:
        by_day[day].setdefault(visitor, wn.source_of(utm, ref))
    return [{"day": d.isoformat(), "visitors": len(by_day[d]),
             "facebook": sum(1 for s in by_day[d].values() if s == "Facebook")} for d in days]


def site_sources(rows, window):
    """[{source, campaign, visitors}], most first: each visitor counted once, by their first row in the window."""
    first = {}
    for day, visitor, utm, campaign, ref in sorted(rows, key=lambda row: row[0]):
        if wn.in_window(day, window) and visitor not in first:
            source = wn.source_of(utm, ref)
            first[visitor] = (source, (campaign or "").strip() if source == "Facebook" else "")
    counts = collections.Counter(first.values())
    return [{"source": s, "campaign": c, "visitors": n}
            for (s, c), n in sorted(counts.items(), key=lambda item: (-item[1], item[0]))]


def usage_table(rows):
    """[{event, people, times}], most people first, from (event, device) rows, without Eric's and App Review's
    installs."""
    people, times = collections.defaultdict(set), collections.Counter()
    for event, device in rows:
        if device not in wn.INTERNAL_INSTALLS:
            people[event].add(device)
            times[event] += 1
    return [{"event": e, "people": len(people[e]), "times": times[e]}
            for e in sorted(times, key=lambda e: (-len(people[e]), -times[e], e))]


def store_days(reports, days, app_id, sku, rates, total_days=DAYS):
    """The App Store numbers for each day Apple has published, and for the last `total_days` of them together (the
    earlier days stay for the ads' before-and-after comparison)."""
    out = []
    for d in days:
        n = wn.app_store_numbers(reports, wn.Window(d, d), app_id, sku, rates)
        if n["report_days"]:
            out.append({"day": d.isoformat(), **{k: n[k] for k in (
                "downloads", "downloads_ios", "downloads_mac", "trials", "pro", "pro_codes", "packs", "proceeds_usd")},
                "unconverted": n["unconverted"]})
    published = [datetime.date.fromisoformat(r["day"]) for r in out][-total_days:]
    total = wn.app_store_numbers(reports, wn.Window(min(published), max(published)), app_id, sku, rates) if out else None
    return out, total


def split_feedback(response, mine):
    """(Eric's count, other testers' feedback) from Apple's betaFeedbackScreenshotSubmissions with tester and build
    included. Other testers' entries keep no name or address."""
    included = {(i["type"], i["id"]): i["attributes"] for i in response.get("included", [])}
    own, others = 0, []
    for item in response.get("data", []):
        a, rel = item["attributes"], item.get("relationships", {})
        tester = (rel.get("tester") or {}).get("data")
        build = (rel.get("build") or {}).get("data")
        email = (included.get(("betaTesters", tester["id"]), {}) if tester else {}).get("email") or ""
        if email.lower() in mine:
            own += 1
            continue
        others.append({"date": (a.get("createdDate") or "")[:16], "platform": a.get("appPlatform"),
                       "build": included.get(("builds", build["id"]), {}).get("version") if build else None,
                       "comment": (a.get("comment") or "").strip()})
    return own, others


SUPPORT_INBOX = "ShowRecorder"  # Chatwoot inboxes whose names start with this are the app's
IN, OUT = 0, 1  # Chatwoot message types; 2 is an activity row


def support_summary(conversations, messages, inboxes, start):
    """The app's support threads from Chatwoot's conversations, each one's messages ({id: [message]}) and the inbox
    names ({id: name}). `waiting`: threads not resolved whose last public message is the customer's, waiting since
    their first message after our last public reply. `new`: threads opened since `start` (aware datetime) per inbox,
    and how many got a public reply. No names, addresses or message text: only the subject is kept."""
    def public(cid):
        return [m for m in messages.get(cid, []) if m["message_type"] in (IN, OUT) and not m.get("private")]

    def iso(t):
        return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat(timespec="minutes")

    ours = [c for c in conversations if (inboxes.get(c["inbox_id"]) or "").startswith(SUPPORT_INBOX)]
    waiting, new = [], collections.OrderedDict()
    for c in sorted(ours, key=lambda c: c["id"]):
        said = public(c["id"])
        inbox = inboxes[c["inbox_id"]]
        if c["status"] != "resolved" and said and said[-1]["message_type"] == IN:
            replies = [i for i, m in enumerate(said) if m["message_type"] == OUT]
            first = said[replies[-1] + 1] if replies else said[0]
            waiting.append({"id": c["id"], "inbox": inbox,
                            "subject": (c.get("additional_attributes") or {}).get("mail_subject"),
                            "status": c["status"], "since": iso(first["created_at"])})
        if c["created_at"] >= start.timestamp():
            counts = new.setdefault(inbox, {"inbox": inbox, "threads": 0, "answered": 0})
            counts["threads"] += 1
            counts["answered"] += any(m["message_type"] == OUT for m in said)
    return {"waiting": waiting, "new": sorted(new.values(), key=lambda r: r["inbox"])}


# ---- Render: the page from numbers.json and the hand-written files. No network.

def esc(value):
    return html.escape(str(value), quote=True)


def money(value):
    return "–" if value is None else f"${value:,.2f}"


def pct(part, whole):
    return f"{part / whole:.1%}" if whole else "–"


def short_day(iso):
    d = datetime.date.fromisoformat(iso[:10])
    return f"{d.month}/{d.day}"


def long_day(iso):
    return datetime.date.fromisoformat(iso[:10]).strftime("%b %-d")


def read_at(iso):
    """'Nov 18, 10:27 ET' from a UTC ISO time."""
    from zoneinfo import ZoneInfo
    t = datetime.datetime.fromisoformat(iso).astimezone(ZoneInfo(TIME_ZONE))
    return t.strftime("%b %-d, %-H:%M ET")


def table(head, rows, right=()):
    th = "".join(f'<th class="r">{esc(h)}</th>' if i in right else f"<th>{esc(h)}</th>" for i, h in enumerate(head))
    body = "".join("<tr>" + "".join(f'<td class="r">{c}</td>' if i in right else f"<td>{c}</td>"
                                    for i, c in enumerate(r)) + "</tr>\n" for r in rows)
    return f'<div class="tablewrap"><table><thead><tr>{th}</tr></thead><tbody>\n{body}</tbody></table></div>'


def points(items):
    return '<ul class="points">' + "".join(f"<li>{i}</li>" for i in items) + "</ul>" if items else ""


def section(title, src, *parts):
    return (f'<section><div class="head"><h2>{esc(title)}</h2><span class="src">{esc(src)}</span></div>'
            + "".join(p for p in parts if p) + "</section>")


def chip(level, text):
    return f'<span class="chip {esc(level)}">{esc(text)}</span>'


REVIEW_CHIPS = {"APPROVED": ("good", "Testing"), "WAITING_FOR_REVIEW": ("warn", "Waiting for review"),
                "IN_REVIEW": ("warn", "In review"), "REJECTED": ("bad", "Rejected"), "NOT_SUBMITTED": ("info", "Not submitted")}


def window_visitors(daily, start, days):
    """Average visitors a day over `days` complete days from `start` (ISO), or None if there are none."""
    first = datetime.date.fromisoformat(start)
    picked = [r["visitors"] for r in daily if 0 <= (datetime.date.fromisoformat(r["day"]) - first).days < days]
    return sum(picked) / len(picked) if picked else None


def downloads_between(store_daily, start, days):
    first = datetime.date.fromisoformat(start)
    picked = [r["downloads"] for r in store_daily if 0 <= (datetime.date.fromisoformat(r["day"]) - first).days < days]
    return sum(picked) if len(picked) == days else None


def render(n, ads=None, glitchtip=None, notes=None):
    notes = notes or {}
    site, store, tf = n["site"], n["store"], n["testflight"]
    total = store["total"] or {}
    downloads, pro, trials = total.get("downloads") or 0, total.get("pro") or 0, total.get("trials") or 0
    span = f'{long_day(store["first"])} – {long_day(store["last"])}' if store["first"] else "no reports yet"
    complete = [r for r in site["daily"] if r["day"] < n["today"]]
    shown = [r for r in store["daily"] if store["first"] and r["day"] >= store["first"]]

    # Summary strip.
    tiles = [(downloads, f'App Store downloads, {span} ({total.get("downloads_ios") or 0} iPhone/iPad, '
                         f'{total.get("downloads_mac") or 0} Mac)'),
             (pro, f'Pro purchases, from {trials} trials · about {money(total.get("proceeds_usd"))} proceeds')]
    if ads:
        spent = sum(a["spent"] for a in ads["ads"])
        tiles.append((money(spent), f'Ad spend of {money(ads.get("budget"))} · Ads Manager, {ads["range"]}'))
    else:
        tiles.append((sum(r["visitors"] for r in complete[-7:]), "Site visitors, the last 7 complete days"))
    check = notes.get("price_check")
    rate = pct(pro, downloads)
    tiles.append((rate, "Downloads that bought Pro" + (f' ({esc(check["label"])} needs ≥ {check["needs"]:.1%})'
                                                       if check else "")))
    strip = '<div class="strip" aria-label="Summary">' + "".join(
        f'<div><span class="big">{esc(v)}</span><span class="lbl">{l}</span></div>' for v, l in tiles) + "</div>"

    # Website.
    sources = site["sources"]
    by_tag = {r["campaign"]: r["visitors"] for r in sources if r["campaign"]}
    web_points = []
    if ads and ads.get("start"):
        start = datetime.date.fromisoformat(ads["start"])
        after_days = [r for r in complete if r["day"] >= ads["start"]]
        before = window_visitors(complete, (start - datetime.timedelta(days=7)).isoformat(), 7)
        if after_days and before is not None:
            after = sum(r["visitors"] for r in after_days) / len(after_days)
            web_points.append(f'From <strong>{long_day(ads["start"])}</strong>, when the ads started, to '
                              f'{long_day(after_days[-1]["day"])} the site averaged <strong>{after:.0f}</strong> '
                              f"visitors a day, against {before:.0f} the week before.")
    if complete:
        last = complete[-1]
        web_points.append(f'{long_day(last["day"])} had {last["visitors"]} visitors ({last["facebook"]} from Facebook). '
                          f"Today is a part day.")
    for name in ("ChatGPT", "Search"):
        count = sum(r["visitors"] for r in sources if r["source"] == name)
        if count:
            web_points.append(f"{name} sent {count} visitors, with no ads or posts behind them.")
    if site.get("app_store_clicks") is not None:
        web_points.append(f'{site["app_store_clicks"]} App Store button taps on the site in these days.')
    source_rows = [[esc(r["source"]), esc(r["campaign"] or "–"), r["visitors"]] for r in sources[:16]]
    website = section("Website", f'showrecorder.app · PostHog, {long_day(site["daily"][0]["day"])} – '
                                 f'{long_day(site["daily"][-1]["day"])} · {read_at(n["collected_at"])}',
                      points(web_points),
                      '<div class="chart"><div class="legend"><span><i style="background:var(--accent)"></i>From '
                      'Facebook</span><span><i style="background:var(--accent-soft)"></i>Everything else</span>'
                      '<span>The last day is a part day</span></div><svg id="visitors" viewBox="0 0 760 230" '
                      'role="img" aria-label="Daily site visitors split by Facebook and other sources"></svg></div>',
                      table(["Source", "Campaign tag", "Visitors"], source_rows, right=(2,)))

    # Facebook ads.
    ads_html = ""
    if ads:
        rows, best = [], max(ads["ads"], key=lambda a: a["clicks"] / a["impressions"] if a["impressions"] else 0)
        for a in ads["ads"]:
            mark = ' best' if a is best else ""
            rows.append([esc(a["name"]), money(a["spent"]), f'{a["impressions"]:,}', f'{a["reach"]:,}', a["clicks"],
                         f'<span class="{mark.strip()}">{pct(a["clicks"], a["impressions"])}</span>',
                         money(a["spent"] / a["clicks"]) if a["clicks"] else "–", by_tag.get(a["tag"], 0)])
        spent = sum(a["spent"] for a in ads["ads"])
        clicks = sum(a["clicks"] for a in ads["ads"])
        shows = sum(a["impressions"] for a in ads["ads"])
        rows.append(["<strong>Total</strong>", f"<strong>{money(spent)}</strong>", f"{shows:,}", "–", clicks,
                     pct(clicks, shows), money(spent / clicks) if clicks else "–",
                     sum(by_tag.get(a["tag"], 0) for a in ads["ads"])])
        ad_points = [esc(x) for x in ads.get("notices", [])]
        if ads.get("start"):
            start = datetime.date.fromisoformat(ads["start"])
            after = downloads_between(store["daily"], ads["start"], 7)
            before = downloads_between(store["daily"], (start - datetime.timedelta(days=7)).isoformat(), 7)
            if after is not None and before is not None:
                extra = after - before
                cost = f" If the ads caused the difference, that's about <strong>{money(spent / extra)} per extra " \
                       f"download</strong>." if extra > 0 else ""
                ad_points.append(f"Downloads were <strong>{after}</strong> in the 7 days from {long_day(ads['start'])}, "
                                 f"against {before} in the 7 days before.{cost} Nothing ties a click to a download yet.")
        ads_html = section("Facebook ads", f'Ads Manager · {ads["range"]} · {read_at(ads["read_at"])}',
                           f'<p><strong>{esc(best["name"])} is the better ad</strong>: '
                           f'{pct(best["clicks"], best["impressions"])} click rate at '
                           f'{money(best["spent"] / best["clicks"]) if best["clicks"] else "–"} a click.</p>',
                           table(["Ad", "Spent", "Impressions", "Reached", "Link clicks", "Click rate", "Per click",
                                  "Site visitors"], rows, right=(1, 2, 3, 4, 5, 6, 7)),
                           points(ad_points))

    # App Store.
    countries = ", ".join(f"{c} {k}" for c, k in list(store["countries"].items())[:5])
    extra = "; also " + ", ".join(f"{c} {v:,.2f}" for c, v in sorted(total.get("unconverted", {}).items())) \
        if total.get("unconverted") else ""
    store_rows = [["Downloads", downloads, esc(countries)], ["Redownloads", store["redownloads"], ""],
                  ["Updates", store["updates"], ""], ["Free trials", trials, ""],
                  ["Pro purchases", pro, f'Plus {total.get("pro_codes") or 0} from offer codes. '
                                         f'Pro purchases are {pct(pro, trials)} of trials started.'],
                  ["Pack purchases", total.get("packs") or 0, ""],
                  ["Proceeds", money(total.get("proceeds_usd")), "Converted to USD at today's rates" + esc(extra)]]
    versions = [f'Live: {esc(v["platform"].replace("MAC_OS", "Mac").replace("IOS", "iOS"))} {esc(v["version"])}'
                for v in tf["store_versions"] if v["state"] == "READY_FOR_SALE"][:1]
    for v in tf["store_versions"]:
        if v["state"] != "READY_FOR_SALE":
            name = "Mac" if v["platform"] == "MAC_OS" else "iOS"
            versions.append(f'<strong>{name} {esc(v["version"])} is “{esc(v["state"].replace("_", " ").capitalize())}”'
                            f"</strong>.")
    versions.append(f'{len(tf["reviews"])} written App Store reviews in the last ten.' if tf["reviews"]
                    else "No written App Store reviews.")
    marker = next((i for i, r in enumerate(shown) if ads and r["day"] == ads.get("start")), None)
    app_store = section("App Store", f"App Store Connect sales reports, {span} · {read_at(n['collected_at'])}",
                        '<div class="chart"><div class="legend"><span><i style="background:var(--accent)"></i>'
                        'Downloads per day</span>' + ('<span>Dashed line: ads start</span>' if marker is not None else "")
                        + '</div><svg id="downloads" viewBox="0 0 760 210" role="img" '
                          'aria-label="App Store downloads per day"></svg></div>',
                        table([f"{len(shown)} days", "Count", "Note"], store_rows, right=(1,)),
                        table(["Day", "Downloads", "Trials", "Pro", "Codes", "Proceeds"],
                              [[long_day(r["day"]), r["downloads"], r["trials"], r["pro"], r["pro_codes"],
                                money(r["proceeds_usd"]) if r["proceeds_usd"] else "–"] for r in shown],
                              right=(1, 2, 3, 4, 5)),
                        points(versions))

    # TestFlight.
    review_rows = []
    for r in tf["beta_review"]:
        level, label = REVIEW_CHIPS.get(r["review"], ("info", r["review"].replace("_", " ").capitalize()))
        review_rows.append([f'<span class="num">{esc(r["version"])} ({esc(r["build"])})</span>',
                            "Mac" if r["platform"] == "MAC_OS" else "iOS", chip(level, label),
                            chip("good" if r["processing"] == "VALID" else "warn", r["processing"].capitalize())])
    testers = tf["testers"]
    tf_points = [f'{sum(testers.values())} TestFlight testers: '
                 + ", ".join(f"{v} {k}" for k, v in sorted(testers.items(), key=lambda kv: -kv[1])) + "."]
    feedback = tf["feedback"]
    tf_points.append(f'{feedback["total"]} screenshot feedback reports, {feedback["mine"]} of them yours.')
    for f in feedback["others"]:
        note = notes.get("feedback_notes", {}).get(f["date"])
        tf_points.append(f'{long_day(f["date"])}, build {esc(f["build"])}: “{esc(f["comment"])}”'
                         + (f" {esc(note)}" if note else ""))
    testflight = section("TestFlight", f"App Store Connect API · {read_at(n['collected_at'])}",
                         table(["Build", "Platform", "Beta App Review", "Processing"], review_rows), points(tf_points))

    # Usage.
    usage = section("App usage", f'PostHog, {long_day(site["daily"][0]["day"])} – {long_day(site["daily"][-1]["day"])} '
                                 "· TestFlight and Debug builds with sharing on · your own devices left out",
                    "<p>Usage comes only from TestFlight and Debug builds where the tester left sharing on, so these "
                    "are testers, not App Store users.</p>",
                    table(["Event", "People", "Times"],
                          [[esc(USAGE_NAMES.get(u["event"], u["event"])), u["people"], u["times"]] for u in n["usage"]],
                          right=(1, 2)))

    # Errors.
    err_rows = []
    if glitchtip is not None:
        app = glitchtip.get("app", [])
        err_rows.append(["GlitchTip, app", chip("bad", f"{len(app)} open") if app else chip("info", "No reports"),
                         esc("; ".join(f'{i["title"]} ({i["count"]}×)' for i in app) or "Nothing received")])
        web = glitchtip.get("web", [])
        err_rows.append(["GlitchTip, website", chip("bad", f"{len(web)} open") if web else chip("good", "None open"),
                         esc("; ".join(f'{i["title"]} ({i["count"]}×)' + (f' {i["note"]}' if i.get("note") else "")
                                       for i in web))])
    err_rows.append(["TestFlight crash reports", chip("bad", str(tf["crashes"])) if tf["crashes"] else
                     chip("good", "None"), "Sent by testers from TestFlight"])
    for d in tf["diagnostics"]:
        sigs = d["signatures"]
        if sigs is None:
            err_rows.append([f'Apple diagnostics, iOS {esc(d["version"])}', chip("info", "Not available"), ""])
        else:
            kinds = collections.Counter(s["type"] for s in sigs)
            err_rows.append([f'Apple diagnostics, iOS {esc(d["version"])}',
                             chip("bad", f"{len(sigs)} signatures") if sigs else chip("good", "None"),
                             esc(", ".join(f"{k.replace('_', ' ').lower()} {v}" for k, v in kinds.items())
                                 or "Hangs, disk writes, slow launches")])
    errors = section("Errors", "GlitchTip " + (read_at(glitchtip["read_at"]) if glitchtip else "not read")
                     + f" · App Store Connect {read_at(n['collected_at'])}", table(["Where", "Result", "Detail"], err_rows))

    # Support.
    support = n.get("support")
    if support is None:
        support_html = section("Support", "Chatwoot not read")
    else:
        now = datetime.datetime.fromisoformat(n["collected_at"])
        waits = [[f'#{w["id"]}', esc(w["inbox"]), esc(w["subject"] or "(no subject)"), esc(read_at(w["since"])),
                  f'{round((now - datetime.datetime.fromisoformat(w["since"])).total_seconds() / 86400)} days',
                  esc(w["status"])] for w in support["waiting"]]
        support_html = section(
            "Support", f"Chatwoot, ShowRecorder inboxes · {read_at(n['collected_at'])}",
            table(["Thread", "Inbox", "Subject", "Waiting since", "Waited", "Status"], waits, right=(4,)) if waits
            else "<p>Nothing is waiting on a reply.</p>",
            points([f'{r["threads"]} new threads in {esc(r["inbox"])}, {r["answered"]} answered (sales emails '
                    "are resolved without one)." for r in support["new"]]))

    extra_sections = "".join(section(s["title"], s.get("src", ""), points([esc(p) for p in s.get("points", [])]))
                             for s in notes.get("sections", []))

    todo = [(t["level"], t["tag"], t["text"]) for t in notes.get("needs_you", [])]
    todo += [("warn", "TestFlight", f'{r["version"]} ({r["build"]}) on {"Mac" if r["platform"] == "MAC_OS" else "iOS"} '
                                    f'is {REVIEW_CHIPS[r["review"]][1].lower()}.')
             for r in tf["beta_review"] if r["review"] in ("WAITING_FOR_REVIEW", "IN_REVIEW", "REJECTED")]
    todo += [("warn", "Support", f'Reply to support thread #{w["id"]} ({w["subject"] or "no subject"}), waiting since '
                                 f'{read_at(w["since"])}.') for w in (support or {}).get("waiting", [])]
    needs = ('<section><div class="head"><h2>Needs you</h2></div><div class="todo">'
             + "".join(f"<div>{chip(level, tag)}<span>{esc(text)}</span></div>" for level, tag, text in todo)
             + "</div></section>") if todo else ""

    chart = {"days": [short_day(r["day"]) for r in site["daily"]],
             "fb": [r["facebook"] for r in site["daily"]],
             "other": [r["visitors"] - r["facebook"] for r in site["daily"]],
             "dl_days": [short_day(r["day"]) for r in shown],
             "dl": [r["downloads"] for r in shown], "marker": marker}
    updated = read_at(n["collected_at"])
    return (PAGE_HEAD + f'<main><header><div class="eyebrow">ShowRecorder · updated {esc(updated)}</div>'
            "<h1>ShowRecorder numbers</h1><p class=\"lede\">The last two weeks of website traffic, Facebook ads, App "
            "Store sales, TestFlight, tester usage and errors. Each section says when its numbers were read.</p>"
            f"</header>{strip}{website}{ads_html}{app_store}{testflight}{usage}{errors}{support_html}{extra_sections}"
            f"{needs}<footer>Built by scripts/numbers_report.py from PostHog (Owned Sites), App Store Connect, Chatwoot, "
            "and hand-read "
            "Facebook Ads Manager and GlitchTip numbers.</footer></main>"
            f"<script>var D = {json.dumps(chart)};\n{CHART_JS}</script>\n")


PAGE_HEAD = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ShowRecorder Numbers</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
:root { --bg: #f6f7f9; --surface: #ffffff; --fg: #16202b; --muted: #5b6875; --line: #dde2e8;
  --accent: #1f5fbf; --accent-soft: #d6e3f7; --good: #1d7a4a; --warn: #a8610a; --bad: #b2332b;
  --chip-good: #dcf1e5; --chip-warn: #fbecd3; --chip-bad: #f8dcd9;
  --font-display: "Instrument Sans", "Inter", system-ui, sans-serif;
  --font-body: "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
  --font-data: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #0f141a; --surface: #161d25; --fg: #e5ebf1; --muted: #93a1af; --line: #2a3440;
  --accent: #6ea2ef; --accent-soft: #1d3355; --good: #5cc98d; --warn: #e8a64a; --bad: #ef7d73;
  --chip-good: #17382a; --chip-warn: #3d2c12; --chip-bad: #42201d; color-scheme: dark; } }
:root[data-theme="dark"] { --bg: #0f141a; --surface: #161d25; --fg: #e5ebf1; --muted: #93a1af; --line: #2a3440;
  --accent: #6ea2ef; --accent-soft: #1d3355; --good: #5cc98d; --warn: #e8a64a; --bad: #ef7d73;
  --chip-good: #17382a; --chip-warn: #3d2c12; --chip-bad: #42201d; color-scheme: dark; }
* { box-sizing: border-box; }
body { background: var(--bg); color: var(--fg); font-family: var(--font-body); font-size: 15px; line-height: 1.55;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 32px 64px; margin: 0; }
main { max-width: 860px; margin: 0 auto; display: grid; gap: 40px; }
h1, h2 { font-family: var(--font-display); text-wrap: balance; margin: 0; letter-spacing: -0.01em; }
h1 { font-size: clamp(28px, 5vw, 38px); font-weight: 700; } h2 { font-size: 21px; font-weight: 600; }
p { margin: 0; max-width: 68ch; }
.eyebrow { font-family: var(--font-data); font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
header { display: grid; gap: 10px; } header .lede { color: var(--muted); }
.num { font-family: var(--font-data); font-variant-numeric: tabular-nums; }
.strip { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 1px; background: var(--line); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
.strip > div { background: var(--surface); padding: 16px; display: grid; gap: 4px; align-content: start; }
.strip .big { font-family: var(--font-display); font-size: 28px; font-weight: 600; font-variant-numeric: tabular-nums; }
.strip .lbl { font-size: 13px; color: var(--muted); }
@media (max-width: 640px) { .strip { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
section { display: grid; gap: 14px; }
section > .head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 14px; border-top: 1px solid var(--line); padding-top: 18px; }
.src { font-size: 12.5px; color: var(--muted); }
ul.points { margin: 0; padding-left: 20px; display: grid; gap: 6px; max-width: 72ch; }
.tablewrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 8px; background: var(--surface); }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th, td { text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--line); white-space: nowrap; }
tr:last-child td { border-bottom: 0; }
th { font-weight: 600; font-size: 12.5px; color: var(--muted); background: var(--bg); }
td.r, th.r { text-align: right; font-family: var(--font-data); font-variant-numeric: tabular-nums; }
.best { color: var(--good); font-weight: 600; }
.chip { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 9px; border-radius: 999px; white-space: nowrap; }
.chip.good { background: var(--chip-good); color: var(--good); } .chip.warn { background: var(--chip-warn); color: var(--warn); }
.chip.bad { background: var(--chip-bad); color: var(--bad); } .chip.info { background: var(--accent-soft); color: var(--accent); }
.chart { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 14px 12px 8px; overflow-x: auto; }
.chart svg { display: block; width: 100%; min-width: 520px; height: auto; }
.legend { display: flex; flex-wrap: wrap; gap: 6px 16px; font-size: 12.5px; color: var(--muted); padding: 4px 4px 6px; }
.legend i { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 6px; vertical-align: -1px; }
.todo { display: grid; gap: 10px; }
.todo div { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 12px; align-items: start; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; }
footer { color: var(--muted); font-size: 12.5px; border-top: 1px solid var(--line); padding-top: 14px; }
</style></head><body>
"""

CHART_JS = """(function () {
  var NS = "http://www.w3.org/2000/svg";
  function el(n, a, t) { var e = document.createElementNS(NS, n); for (var k in a) e.setAttribute(k, a[k]); if (t != null) e.textContent = t; return e; }
  function scale(max) {
    var step = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000].find(function (s) { return max / s <= 5; }) || 1000;
    var top = Math.max(step, Math.ceil(max / step) * step), ticks = [];
    for (var v = 0; v <= top; v += step) ticks.push(v);
    return { top: top * 1.12, ticks: ticks };
  }
  function chart(id, labels, series, marker) {
    var svg = document.getElementById(id); if (!svg || !labels.length) return;
    var vb = svg.viewBox.baseVal, W = vb.width, H = vb.height, L = 36, R = 8, T = 10, B = 28, pw = W - L - R, ph = H - T - B;
    var totals = labels.map(function (_, i) { return series.reduce(function (s, x) { return s + x.values[i]; }, 0); });
    var sc = scale(Math.max.apply(null, totals.concat([1]))), slot = pw / labels.length, bw = slot * 0.62;
    function y(v) { return T + ph - (v / sc.top) * ph; }
    sc.ticks.forEach(function (t) {
      svg.appendChild(el("line", { x1: L, x2: W - R, y1: y(t), y2: y(t), stroke: "var(--line)", "stroke-width": 1 }));
      svg.appendChild(el("text", { x: L - 6, y: y(t) + 4, "text-anchor": "end", "font-size": 11, fill: "var(--muted)", "font-family": "var(--font-data)" }, t));
    });
    if (marker != null) { var mx = L + slot * marker; svg.appendChild(el("line", { x1: mx, x2: mx, y1: T, y2: T + ph, stroke: "var(--muted)", "stroke-width": 1, "stroke-dasharray": "4 4" })); }
    labels.forEach(function (lab, i) {
      var x = L + slot * i + (slot - bw) / 2, base = 0;
      series.forEach(function (s) { var v = s.values[i]; if (v > 0) svg.appendChild(el("rect", { x: x, y: y(base + v), width: bw, height: y(base) - y(base + v), fill: s.color, rx: 1.5 })); base += v; });
      svg.appendChild(el("text", { x: x + bw / 2, y: y(base) - 4, "text-anchor": "middle", "font-size": 10.5, fill: "var(--fg)", "font-family": "var(--font-data)" }, base));
      svg.appendChild(el("text", { x: x + bw / 2, y: H - 9, "text-anchor": "middle", "font-size": 10.5, fill: "var(--muted)", "font-family": "var(--font-data)" }, lab));
    });
  }
  chart("visitors", D.days, [{ values: D.fb, color: "var(--accent)" }, { values: D.other, color: "var(--accent-soft)" }], null);
  chart("downloads", D.dl_days, [{ values: D.dl, color: "var(--accent)" }], D.marker);
})();"""


# ---- Everything below talks to the network; the tests stop above this line.

def fetch_site(start, end):
    day = f"toDate(toTimeZone(timestamp, '{wn.TIME_ZONE}'))"
    span = f"{day} >= toDate('{start}') AND {day} <= toDate('{end}')"
    site = f"properties.$host = '{wn.SITE}' AND {span}"

    def rows(sql):
        return [(datetime.date.fromisoformat(r[0]), *r[1:]) for r in wn.posthog(sql + " LIMIT 50000")]

    visitors = rows(f"SELECT toString({day}) d, toString(person_id), argMin(properties.utm_source, timestamp), "
                    f"argMin(properties.utm_campaign, timestamp), argMin(properties.$referring_domain, timestamp) "
                    f"FROM events WHERE event = '$pageview' AND {site} GROUP BY d, person_id")
    clicks = rows(f"SELECT toString({day}), toString(uuid) FROM events WHERE {site} AND {wn.APP_STORE_CLICK}")
    usage = [tuple(r) for r in wn.posthog(f"SELECT event, distinct_id FROM events WHERE properties.app = 'showrecorder' "
                                          f"AND {span} LIMIT 50000")]
    return visitors, clicks, usage


CHATWOOT = "https://chatwoot.ericdahl.dev"


def fetch_support(start):
    """support_summary from Chatwoot's API, read only (GET). The token is CHATWOOT_API_ACCESS_TOKEN, from Infisical
    when it isn't set. Reads pages, newest activity first, until a page's threads all went quiet before `start`;
    a thread still open is never that old for long, since `waiting` covers only threads not resolved."""
    import urllib.request
    wn.load_secrets(["CHATWOOT_API_ACCESS_TOKEN"])
    headers = {"api_access_token": os.environ["CHATWOOT_API_ACCESS_TOKEN"]}

    def get(path):
        with urllib.request.urlopen(urllib.request.Request(CHATWOOT + path, headers=headers), timeout=60) as r:
            return json.load(r)

    base = f'/api/v1/accounts/{get("/api/v1/profile")["account_id"]}'
    inboxes = {i["id"]: i["name"] for i in get(base + "/inboxes")["payload"]}
    conversations, page = [], 1
    while True:
        batch = get(f"{base}/conversations?status=all&sort_by=last_activity_at_desc&page={page}")["data"]["payload"]
        conversations += batch
        if not batch or all(c["last_activity_at"] < start.timestamp() for c in batch) or page >= 20:
            break
        page += 1
    wanted = [c for c in conversations if (inboxes.get(c["inbox_id"]) or "").startswith(SUPPORT_INBOX)
              and (c["status"] != "resolved" or c["created_at"] >= start.timestamp())]
    messages = {c["id"]: get(f'{base}/conversations/{c["id"]}/messages')["payload"] for c in wanted}
    return support_summary(conversations, messages, inboxes, start)


def collect(today):
    import asc_stats, ci_profile

    def get(path, query=None):
        try:
            return ci_profile.call("GET", path, query=query)
        except (Exception, SystemExit):  # Apple says 404 for a build with no diagnostics
            return None

    site_start = today - datetime.timedelta(days=DAYS)
    site_days_ = [site_start + datetime.timedelta(days=i) for i in range(DAYS + 1)]
    visitors, clicks, usage = fetch_site(site_start, today)
    window = wn.Window(site_start, today)
    out = {"collected_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="minutes"),
           "today": today.isoformat(),
           "site": {"daily": site_days(visitors, site_days_), "sources": site_sources(visitors, window),
                    "app_store_clicks": sum(1 for d, _ in clicks if wn.in_window(d, window))},
           "usage": usage_table(usage)}
    try:  # a Chatwoot outage leaves the section "not read" rather than losing the rest
        from zoneinfo import ZoneInfo
        out["support"] = fetch_support(datetime.datetime.combine(site_start, datetime.time(), ZoneInfo(TIME_ZONE)))
    except Exception as e:
        print(f"Chatwoot not read: {type(e).__name__}", file=sys.stderr)
        out["support"] = None

    wn.load_asc_secrets()
    mine = {e.strip().lower() for e in os.environ.get("MINE", "").split(",") if e.strip()}
    store_span = [today - datetime.timedelta(days=back) for back in range(2 * DAYS, 0, -1)]
    with asc_stats.asc_key():
        app_id, sku = asc_stats.app_ids()
        reports = wn.fetch_sales_reports(store_span[0], store_span[-1])
        daily, total = store_days(reports, store_span, app_id, sku, wn.usd_rates())
        shown = total["report_days"] if total else []
        summary = asc_stats.summarize({d: reports[d] for d in shown}, app_id, sku)
        out["store"] = {"daily": daily, "total": total, "first": shown[0] if shown else None,
                        "last": shown[-1] if shown else None,
                        "redownloads": summary.units["redownloads"], "updates": summary.units["updates"],
                        "countries": dict(summary.downloads_by_country.most_common(8))}

        versions = get(f"/apps/{app_id}/appStoreVersions", {"limit": 8}) or {"data": []}
        store_versions = [{"platform": v["attributes"]["platform"], "version": v["attributes"]["versionString"],
                           "state": v["attributes"]["appStoreState"]} for v in versions["data"]]
        newest = get("/builds", {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 1,
                                 "include": "preReleaseVersion"}) or {"data": []}
        pre = {i["id"]: i["attributes"]["version"] for i in newest.get("included", [])}
        version = pre.get(newest["data"][0]["relationships"]["preReleaseVersion"]["data"]["id"]) if newest["data"] else None
        reviews = []
        for platform in ("IOS", "MAC_OS"):
            builds = (get("/builds", {"filter[app]": app_id, "filter[preReleaseVersion.version]": version,
                                      "filter[preReleaseVersion.platform]": platform, "sort": "-uploadedDate",
                                      "limit": 1}) or {}).get("data", [])
            if builds:
                b = builds[0]
                sub = (get(f"/builds/{b['id']}/betaAppReviewSubmission") or {}).get("data")
                reviews.append({"version": version, "build": b["attributes"]["version"], "platform": platform,
                                "review": sub["attributes"].get("betaReviewState") if sub else "NOT_SUBMITTED",
                                "processing": b["attributes"]["processingState"]})
        testers = (get("/betaTesters", {"filter[apps]": app_id, "limit": 200}) or {}).get("data", [])
        written = (get(f"/apps/{app_id}/customerReviews", {"sort": "-createdDate", "limit": 10}) or {}).get("data", [])
        feedback = get(f"/apps/{app_id}/betaFeedbackScreenshotSubmissions",
                       {"limit": 100, "sort": "-createdDate", "include": "tester,build"}) or {}
        own, others = split_feedback(feedback, mine)
        crashes = (get(f"/apps/{app_id}/betaFeedbackCrashSubmissions", {"limit": 50}) or {}).get("data", [])
        diagnostics = []
        for v in [v for v in store_versions if v["platform"] == "IOS" and v["state"] == "READY_FOR_SALE"][:3]:
            builds = (get("/builds", {"filter[app]": app_id, "filter[preReleaseVersion.version]": v["version"],
                                      "filter[preReleaseVersion.platform]": "IOS", "sort": "-uploadedDate",
                                      "limit": 1}) or {}).get("data", [])
            found = get(f"/builds/{builds[0]['id']}/diagnosticSignatures", {"limit": 20}) if builds else None
            diagnostics.append({"version": v["version"], "signatures": None if found is None else [
                {"type": s["attributes"].get("diagnosticType"), "weight": s["attributes"].get("weight"),
                 "signature": (s["attributes"].get("signature") or "")[:120]} for s in found.get("data", [])]})
        out["testflight"] = {
            "store_versions": store_versions, "beta_review": reviews,
            "testers": dict(collections.Counter(t["attributes"].get("state", "?").lower() for t in testers)),
            "reviews": [{"date": r["attributes"]["createdDate"][:10], "rating": r["attributes"]["rating"]}
                        for r in written],
            "feedback": {"total": len(feedback.get("data", [])), "mine": own, "others": others},
            "crashes": len(crashes), "diagnostics": diagnostics}
    return out


def load(name):
    path = os.path.join(DIR, name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    if command == "collect":
        today = datetime.date.fromisoformat(os.environ["TODAY"]) if os.environ.get("TODAY") else datetime.date.today()
        numbers = collect(today)
        with open(os.path.join(DIR, "numbers.json"), "w") as f:
            json.dump(numbers, f, indent=1)
        total = numbers["store"]["total"] or {}
        print(f"wrote {DIR}/numbers.json: {total.get('downloads')} downloads "
              f"{numbers['store']['first']}..{numbers['store']['last']}, "
              f"review {[(r['platform'], r['review']) for r in numbers['testflight']['beta_review']]}")
    elif command == "render":
        page = render(load("numbers.json"), load("ads.json"), load("glitchtip.json"), load("notes.json"))
        path = os.path.join(DIR, "showrecorder-numbers.html")
        with open(path, "w") as f:
            f.write(page)
        print(f"wrote {path}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
