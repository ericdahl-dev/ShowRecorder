#!/usr/bin/env python3
"""App Store downloads per campaign tag (the ct= on our App Store links).

Reads Apple's "App Downloads Detailed" analytics report, the only downloads report with a Campaign column. It comes
from the app's ONGOING analytics report request, which Apple fills with one report instance per processing day.
Apple leaves out rows below its privacy threshold, so the totals can be lower than the sales reports (asc_stats.py).

  doppler run -p ericdahl-dev -c prd -- python3 scripts/asc_campaigns.py              # print by day and campaign
  ... python3 scripts/asc_campaigns.py --json DIR                                     # also write campaign_downloads.json
  ... python3 scripts/asc_campaigns.py --create-request                               # only if the app has no ONGOING request

The App Store Connect key comes from Infisical as in weekly_numbers.py. Never prints the key or a token.
"""
import argparse, collections, csv, gzip, io, json, os, sys, urllib.request

APP_ID = "6820213310"
REPORT = "App Downloads Detailed"

KINDS = {"First-time download": "first", "Redownload": "redownloads"}  # updates and restores are left out
NO_TAG = "(no tag)"  # App Store search, browse, or a link without ct=


def downloads_by_day(texts):
    """{(day, campaign): {"first": n, "redownloads": n}} from report texts (tab-separated, one per segment)."""
    days = collections.defaultdict(lambda: {"first": 0, "redownloads": 0})
    for text in texts:
        for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
            kind = KINDS.get(row["Download Type"])
            if kind:
                days[(row["Date"], row["Campaign"].strip() or NO_TAG)][kind] += int(row["Counts"])
    return dict(days)


def totals(days):
    """[{"campaign", "first", "redownloads"}] over all days, the most first-time downloads first."""
    sums = collections.defaultdict(lambda: {"first": 0, "redownloads": 0})
    for (_, campaign), counts in days.items():
        for kind, n in counts.items():
            sums[campaign][kind] += n
    rows = [{"campaign": c, **n} for c, n in sums.items()]
    return sorted(rows, key=lambda r: (-r["first"], -r["redownloads"], r["campaign"]))


def render(days):
    """The printed report."""
    if not days:
        return ("No campaign downloads yet. Apple publishes the report a day or two after a download, and leaves out "
                "rows below its privacy threshold.")
    width = max(len(campaign) for _, campaign in days)

    def line(campaign, n):
        return f"{campaign:{width}}  first {n['first']}  redownloads {n['redownloads']}"

    lines = ["Downloads by day and campaign (first-time downloads, redownloads):"]
    lines += [f"{day}  {line(campaign, n)}" for (day, campaign), n in sorted(days.items())]
    lines += ["", "Totals:"] + ["  " + line(r["campaign"], r) for r in totals(days)]
    return "\n".join(lines)


def as_json(days):
    """campaign_downloads.json: one row per day and campaign in date order, and the totals."""
    rows = [{"date": day, "campaign": campaign, **n} for (day, campaign), n in sorted(days.items())]
    return {"days": rows, "totals": totals(days)}


# Network: everything below talks to App Store Connect.

def get_all(path, query=None):
    """Every item of a paged list."""
    import ci_profile
    items, page = [], ci_profile.call("GET", path, query={**(query or {}), "limit": 200})
    while True:
        items += page["data"]
        next_url = page.get("links", {}).get("next")
        if not next_url:
            return items
        page = ci_profile.call("GET", next_url[len(ci_profile.API):])


def ongoing_request(create):
    """The app's ONGOING analytics report request id, or None. With create, makes one when there is none."""
    import ci_profile
    for request in get_all(f"/apps/{APP_ID}/analyticsReportRequests"):
        if request["attributes"]["accessType"] == "ONGOING":
            return request["id"]
    if not create:
        return None
    body = {"data": {"type": "analyticsReportRequests", "attributes": {"accessType": "ONGOING"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}
    return ci_profile.call("POST", "/analyticsReportRequests", body=body)["data"]["id"]


def report_texts(request_id):
    """The text of every segment of every daily instance of the report; [] when Apple has none yet."""
    import ci_profile
    reports = get_all(f"/analyticsReportRequests/{request_id}/reports", {"filter[category]": "COMMERCE"})
    report = next((r for r in reports if r["attributes"]["name"] == REPORT), None)
    if report is None:
        return []
    texts = []
    for instance in get_all(f"/analyticsReports/{report['id']}/instances", {"filter[granularity]": "DAILY"}):
        for segment in get_all(f"/analyticsReportInstances/{instance['id']}/segments"):
            with urllib.request.urlopen(segment["attributes"]["url"]) as response:  # a signed URL, no key sent
                texts.append(gzip.decompress(response.read()).decode())
    return texts


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", metavar="DIR", help="write campaign_downloads.json here")
    ap.add_argument("--create-request", action="store_true", help="create the ONGOING report request if missing")
    a = ap.parse_args()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import asc_stats, weekly_numbers
    weekly_numbers.load_asc_secrets()
    with asc_stats.asc_key():
        request_id = ongoing_request(a.create_request)
        if request_id is None:
            sys.exit("ShowRecorder has no ONGOING analytics report request. Run again with --create-request.")
        days = downloads_by_day(report_texts(request_id))
    print(render(days))
    if a.json:
        os.makedirs(a.json, exist_ok=True)
        with open(os.path.join(a.json, "campaign_downloads.json"), "w") as f:
            json.dump(as_json(days), f, indent=1)


if __name__ == "__main__":
    main()
