#!/usr/bin/env python3
"""App Store numbers for ShowRecorder: downloads, updates, re-downloads, free trials and Pro purchases from the daily
sales reports.

Run it with the key from Infisical (project showrecorder, prod), which never shows the secrets:
  infisical run --projectId <showrecorder project ID> --env prod -- python3 scripts/asc_stats.py
Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_VENDOR_NUMBER, and ASC_KEY_PATH or ASC_KEY_P8 (the key itself, written
to a private temporary file for the run). DAYS sets how far back to look (default 30). Apple publishes a day's
report the next day, and none for days before the app's first sale. Never prints the key or a token.
"""
import base64, collections, contextlib, csv, dataclasses, datetime, gzip, io, os, sys, tempfile, urllib.error, urllib.parse, urllib.request

BUNDLE_ID = "dev.ericdahl.ShowRecorder"

# Apple's product type identifiers: iPhone/iPad/universal, then Mac (F...).
KINDS = {
    **dict.fromkeys(("1", "1F", "1T", "F1"), "downloads"),
    **dict.fromkeys(("7", "7F", "7T", "F7"), "updates"),
    **dict.fromkeys(("3", "3F", "3T", "F3"), "redownloads"),
}
PURCHASES = ("IA", "FI")  # in-app purchases (Pro) on iPhone, on Mac
TRIAL_SUFFIX = ".trial"  # the free Trial in-app purchase (dev.ericdahl.ShowRecorder.trial), $0, not a sale
PACK_MARKERS = (".pack.", ".upgrade.")  # mixer packs and the pack-to-Pro upgrade, counted apart from Pro
MAC_DEVICE = "Desktop"  # the iPhone app on an Apple Silicon Mac, until the Mac app ships (its rows are F1)


@dataclasses.dataclass
class Summary:
    units: collections.Counter = dataclasses.field(default_factory=collections.Counter)
    proceeds: dict = dataclasses.field(default_factory=dict)  # currency -> what Apple pays out for Pro
    downloads_by_day: dict = dataclasses.field(default_factory=dict)
    downloads_by_country: collections.Counter = dataclasses.field(default_factory=collections.Counter)
    downloads_by_platform: collections.Counter = dataclasses.field(default_factory=collections.Counter)  # iOS, Mac


def summarize(reports, app_id, sku):
    """Totals for one app from {day: report text}."""
    summary = Summary()
    for day, text in sorted(reports.items()):
        summary.downloads_by_day[day] = 0
        for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
            kind, units = row["Product Type Identifier"], int(float(row["Units"]))
            if row["Parent Identifier"].strip() == sku and row["SKU"].endswith(TRIAL_SUFFIX):
                summary.units["trials"] += units
                continue
            if row["Parent Identifier"].strip() == sku and kind.startswith(PURCHASES):
                if any(marker in row["SKU"] for marker in PACK_MARKERS):
                    summary.units["packs"] += units
                elif float(row.get("Customer Price") or 1) == 0:
                    summary.units["pro_codes"] += units  # Pro from an offer code: no sale
                    continue
                else:
                    summary.units["pro"] += units
                currency = row["Currency of Proceeds"]
                total = summary.proceeds.get(currency, 0) + units * float(row["Developer Proceeds"] or 0)
                summary.proceeds[currency] = round(total, 2)
                continue
            if row["Apple Identifier"] != app_id:
                continue
            if kind in KINDS:
                summary.units[KINDS[kind]] += units
            if KINDS.get(kind) == "downloads":
                summary.downloads_by_day[day] += units
                summary.downloads_by_country[row["Country Code"]] += units
                mac = kind.startswith("F") or row.get("Device") == MAC_DEVICE
                summary.downloads_by_platform["Mac" if mac else "iOS"] += units
    return summary


def sales_report(day):
    """The day's summary sales report as text, or None when Apple has none (404)."""
    import ci_profile
    query = {"filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
             "filter[vendorNumber]": os.environ["ASC_VENDOR_NUMBER"], "filter[reportDate]": day, "filter[version]": "1_1"}
    request = urllib.request.Request(ci_profile.API + "/salesReports?" + urllib.parse.urlencode(query))
    request.add_header("Authorization", "Bearer " + ci_profile.token())
    request.add_header("Accept", "application/a-gzip")  # anything else gets a 406
    try:
        with urllib.request.urlopen(request) as response:
            return gzip.decompress(response.read()).decode()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        sys.exit(f"App Store Connect said {error.code} for the {day} sales report: {error.read().decode()[:300]}")


def report_app(days):
    import ci_profile
    app_id, sku = app_ids()
    print(f"ShowRecorder ({app_id})")

    versions = ci_profile.call("GET", f"/apps/{app_id}/appStoreVersions", query={"limit": 6})["data"]
    print("\nApp Store versions:")
    for v in versions:
        a = v["attributes"]
        print(f"  {a['platform']:8} {a['versionString']:8} {a['appStoreState']}")

    builds = ci_profile.call("GET", "/builds", query={"filter[app]": app_id, "sort": "-uploadedDate", "limit": 4})["data"]
    print("\nNewest TestFlight builds:")
    for b in builds:
        a = b["attributes"]
        print(f"  {a['version']:6} uploaded {a['uploadedDate'][:16]}  {a['processingState']}")

    testers = ci_profile.call("GET", "/betaTesters", query={"filter[apps]": app_id, "limit": 200})["data"]
    states = collections.Counter(t["attributes"].get("state", "?").lower() for t in testers)
    print(f"\nTestFlight testers: {len(testers)} ({', '.join(f'{n} {s}' for s, n in states.most_common())})")

    reviews = ci_profile.call("GET", f"/apps/{app_id}/customerReviews", query={"sort": "-createdDate", "limit": 5})["data"]
    print(f"\nNewest reviews: {len(reviews) or 'none'}")
    for r in reviews:
        a = r["attributes"]
        print(f"  {a['createdDate'][:10]} {a['rating']}/5 {a['territory']}: {a.get('title', '')}")

    today = datetime.date.today()
    reports = {}
    for back in range(1, days + 1):
        day = (today - datetime.timedelta(days=back)).isoformat()
        text = sales_report(day)
        if text is not None:
            reports[day] = text
    summary = summarize(reports, app_id, sku)
    if not reports:
        print(f"\nNo sales reports in the last {days} days.")
        return
    first, last = min(reports), max(reports)
    print(f"\nSales {first} to {last} ({len(reports)} days with a report):")
    for kind in ("downloads", "redownloads", "updates", "trials", "pro", "pro_codes", "packs"):
        print(f"  {kind}: {summary.units[kind]}")
    print("  Pro proceeds: " + (", ".join(f"{c} {v:.2f}" for c, v in sorted(summary.proceeds.items())) or "none"))
    print("  downloads by country: " + ", ".join(f"{c} {n}" for c, n in summary.downloads_by_country.most_common(8)))
    print("  downloads by day: " + ", ".join(f"{d[5:]} {n}" for d, n in summary.downloads_by_day.items()))


@contextlib.contextmanager
def asc_key():
    """Sets ASC_KEY_PATH for ci_profile.token(): as given, or ASC_KEY_P8 written to a private temporary file that
    is removed afterwards."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if os.environ.get("ASC_KEY_PATH"):
        yield
        return
    key = os.environ["ASC_KEY_P8"]
    if "BEGIN" not in key:
        key = base64.b64decode(key).decode()
    fd, path = tempfile.mkstemp(suffix=".p8")  # readable only by us
    try:
        os.write(fd, key.encode())
        os.close(fd)
        os.environ["ASC_KEY_PATH"] = path
        yield
    finally:
        os.environ.pop("ASC_KEY_PATH", None)
        os.unlink(path)


def app_ids():
    """(Apple ID, SKU) of ShowRecorder."""
    import ci_profile
    app = ci_profile.call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID})["data"][0]
    return app["id"], app["attributes"]["sku"]


def main():
    with asc_key():
        report_app(int(os.environ.get("DAYS", "30")))


if __name__ == "__main__":
    main()
