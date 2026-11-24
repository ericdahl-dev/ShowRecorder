#!/usr/bin/env python3
"""Tests for numbers_report.py: the numbers it collects and the page it renders. No network, no keys.
Run: python3 scripts/test_numbers_report.py"""
import datetime, os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numbers_report as nr
import weekly_numbers as wn
from test_asc_stats import report

D = datetime.date


class SiteTests(unittest.TestCase):
    ROWS = [
        (D(2026, 11, 10), "a", "facebook", "fbad-x32", ""),
        (D(2026, 11, 10), "b", "", "", "m.facebook.com"),
        (D(2026, 11, 10), "c", "", "", "chatgpt.com"),
        (D(2026, 11, 11), "a", "", "", ""),
        (D(2026, 11, 11), "d", "facebook", "x32-group-app", ""),
    ]

    def test_counts_visitors_and_facebook_visitors_per_day(self):
        days = nr.site_days(self.ROWS, [D(2026, 11, 9), D(2026, 11, 10), D(2026, 11, 11)])
        self.assertEqual(days, [{"day": "2026-11-09", "visitors": 0, "facebook": 0},
                                {"day": "2026-11-10", "visitors": 3, "facebook": 2},
                                {"day": "2026-11-11", "visitors": 2, "facebook": 1}])

    def test_counts_each_visitor_once_by_their_first_source_and_campaign(self):
        sources = nr.site_sources(self.ROWS, wn.Window(D(2026, 11, 10), D(2026, 11, 11)))
        self.assertEqual(sources, [{"source": "ChatGPT", "campaign": "", "visitors": 1},
                                   {"source": "Facebook", "campaign": "", "visitors": 1},
                                   {"source": "Facebook", "campaign": "fbad-x32", "visitors": 1},
                                   {"source": "Facebook", "campaign": "x32-group-app", "visitors": 1}])


class UsageTests(unittest.TestCase):
    def test_counts_people_and_times_without_internal_installs(self):
        eric = next(iter(wn.INTERNAL_INSTALLS))
        rows = [("take_started", "x"), ("take_started", "x"), ("take_started", "y"), ("app_opened", "x"),
                ("take_started", eric)]
        unknown = wn.UNKNOWN_SOURCE
        self.assertEqual(nr.usage_table(rows), [{"event": "take_started", "source": unknown, "people": 2, "times": 3},
                                                {"event": "app_opened", "source": unknown, "people": 1, "times": 1}])

    def test_splits_each_event_by_source(self):
        rows = [("take_started", "a", "testflight"), ("take_started", "b", "appstore"),
                ("take_started", "c", "appstore"), ("app_opened", "a", "testflight")]
        self.assertEqual(nr.usage_table(rows), [
            {"event": "take_started", "source": "App Store", "people": 2, "times": 2},
            {"event": "take_started", "source": "TestFlight", "people": 1, "times": 1},
            {"event": "app_opened", "source": "TestFlight", "people": 1, "times": 1}])


class StoreTests(unittest.TestCase):
    def test_gives_each_published_day_and_the_total(self):
        pro = {"Product Type Identifier": "IA1", "SKU": "pro", "Parent Identifier": "showrecorder",
               "Developer Proceeds": "3.50", "Apple Identifier": "proid"}
        reports = {"2026-11-14": report({"Product Type Identifier": "1", "Units": "4"}, pro),
                   "2026-11-15": report({"Product Type Identifier": "1F", "Units": "2"})}
        days = [D(2026, 11, 13), D(2026, 11, 14), D(2026, 11, 15)]
        daily, total = nr.store_days(reports, days, "app", "showrecorder", {"USD": 1})
        _, last_day = nr.store_days(reports, days, "app", "showrecorder", {"USD": 1}, total_days=1)
        self.assertEqual(last_day["report_days"], ["2026-11-15"])
        self.assertEqual([(r["day"], r["downloads"], r["pro"], r["proceeds_usd"]) for r in daily],
                         [("2026-11-14", 4, 1, 3.5), ("2026-11-15", 2, 0, 0.0)])
        self.assertEqual((total["downloads"], total["pro"], total["report_days"]), (6, 1, ["2026-11-14", "2026-11-15"]))

    def test_no_published_day_means_no_total(self):
        self.assertEqual(nr.store_days({}, [D(2026, 11, 15)], "app", "showrecorder", {"USD": 1}), ([], None))


class FeedbackTests(unittest.TestCase):
    def test_counts_erics_feedback_and_lists_the_rest_without_names(self):
        response = {
            "data": [
                {"attributes": {"createdDate": "2026-11-14T17:24:00Z", "comment": " Delete is hard ", "appPlatform": "IOS"},
                 "relationships": {"tester": {"data": {"id": "t1"}}, "build": {"data": {"id": "b1"}}}},
                {"attributes": {"createdDate": "2026-11-13T10:00:00Z", "comment": "mine"},
                 "relationships": {"tester": {"data": {"id": "t2"}}}},
            ],
            "included": [
                {"type": "betaTesters", "id": "t1", "attributes": {"email": "tester@example.com", "firstName": "Pat"}},
                {"type": "betaTesters", "id": "t2", "attributes": {"email": "Eric@Example.com"}},
                {"type": "builds", "id": "b1", "attributes": {"version": "61.1"}},
            ],
        }
        own, others = nr.split_feedback(response, {"eric@example.com"})
        self.assertEqual(own, 1)
        self.assertEqual(others, [{"date": "2026-11-14T17:24", "platform": "IOS", "build": "61.1",
                                   "comment": "Delete is hard"}])


def ts(text):
    """Unix time of an ISO UTC time, as Chatwoot sends it."""
    return int(datetime.datetime.fromisoformat(text + "+00:00").timestamp())


def message(kind, at, private=False):
    return {"message_type": kind, "created_at": ts(at), "private": private}


class SupportTests(unittest.TestCase):
    INBOXES = {1: "ShowRecorder", 2: "ShowRecorder Website", 3: "Other Site Support"}
    START = datetime.datetime(2026, 11, 8, tzinfo=datetime.timezone.utc)

    def conv(self, cid, inbox, status, created, subject=None):
        return {"id": cid, "inbox_id": inbox, "status": status, "created_at": ts(created),
                "additional_attributes": {"mail_subject": subject} if subject else {}}

    def test_a_thread_waits_from_the_first_customer_message_after_our_last_public_reply(self):
        convs = [self.conv(7, 1, "open", "2026-11-10T09:00", "USB error")]
        msgs = {7: [message(0, "2026-11-10T09:00"), message(1, "2026-11-11T10:00"),
                    message(0, "2026-11-12T08:00"), message(1, "2026-11-12T09:00", private=True),
                    message(2, "2026-11-12T09:01"), message(0, "2026-11-13T07:00")]}
        support = nr.support_summary(convs, msgs, self.INBOXES, self.START)
        self.assertEqual(support["waiting"], [{"id": 7, "inbox": "ShowRecorder", "subject": "USB error",
                                               "status": "open", "since": "2026-11-12T08:00+00:00"}])

    def test_answered_resolved_and_other_inboxes_dont_wait(self):
        convs = [self.conv(1, 1, "open", "2026-11-10T09:00"), self.conv(2, 1, "resolved", "2026-11-10T09:00"),
                 self.conv(3, 3, "open", "2026-11-10T09:00"), self.conv(4, 2, "snoozed", "2026-11-10T09:00")]
        msgs = {1: [message(0, "2026-11-10T09:00"), message(1, "2026-11-10T10:00")],
                2: [message(0, "2026-11-10T09:00")], 3: [message(0, "2026-11-10T09:00")],
                4: [message(0, "2026-11-10T09:00"), message(1, "2026-11-10T10:00")]}
        self.assertEqual(nr.support_summary(convs, msgs, self.INBOXES, self.START)["waiting"], [])

    def test_counts_new_threads_per_inbox_in_the_window_and_how_many_we_answered(self):
        convs = [self.conv(1, 1, "resolved", "2026-11-10T09:00"), self.conv(2, 1, "resolved", "2026-11-12T09:00"),
                 self.conv(3, 2, "open", "2026-11-14T09:00"), self.conv(4, 1, "resolved", "2026-11-01T09:00"),
                 self.conv(5, 3, "open", "2026-11-14T09:00")]
        msgs = {1: [message(0, "2026-11-10T09:00"), message(1, "2026-11-10T10:00")],
                2: [message(0, "2026-11-12T09:00")], 3: [message(0, "2026-11-14T09:00")],
                4: [message(0, "2026-11-01T09:00")], 5: [message(0, "2026-11-14T09:00")]}
        self.assertEqual(nr.support_summary(convs, msgs, self.INBOXES, self.START)["new"],
                         [{"inbox": "ShowRecorder", "threads": 2, "answered": 1},
                          {"inbox": "ShowRecorder Website", "threads": 1, "answered": 0}])


class EngineeringTests(unittest.TestCase):
    def test_keeps_the_newest_run_of_each_workflow_per_branch(self):
        runs = {"main": [{"workflowName": "CI", "conclusion": "failure", "status": "completed",
                          "createdAt": "2026-11-20T10:00:00Z", "displayTitle": "Newer", "url": "u2"},
                         {"workflowName": "CI", "conclusion": "success", "status": "completed",
                          "createdAt": "2026-11-19T10:00:00Z", "displayTitle": "Older", "url": "u1"}]}
        eng = nr.engineering_summary(runs, [], [], [], 0)
        self.assertEqual(eng["ci"], [{"branch": "main", "workflow": "CI", "result": "failure",
                                      "at": "2026-11-20T10:00:00Z", "title": "Newer", "url": "u2"}])

    def test_a_run_in_progress_shows_its_status(self):
        runs = {"release/1.2": [{"workflowName": "CI", "conclusion": "", "status": "in_progress",
                                 "createdAt": "2026-11-20T10:00:00Z", "displayTitle": "Fix", "url": "u"}]}
        self.assertEqual(nr.engineering_summary(runs, [], [], [], 0)["ci"][0]["result"], "in_progress")

    def test_lists_uploads_prs_and_bugs(self):
        uploads = [{"headBranch": "v1.2.14", "conclusion": "success", "status": "completed",
                    "createdAt": "2026-11-18T00:42:02Z"}]
        prs = [{"number": 9, "title": "Draft thing", "createdAt": "2026-11-10T00:00:00Z", "isDraft": True}]
        bugs = [{"number": 5, "title": "Crash", "createdAt": "2026-11-01T00:00:00Z", "labels": [{"name": "P1"}]}]
        eng = nr.engineering_summary({}, uploads, prs, bugs, 74)
        self.assertEqual(eng["uploads"], [{"tag": "v1.2.14", "result": "success", "at": "2026-11-18T00:42:02Z"}])
        self.assertEqual(eng["prs"], [{"number": 9, "title": "Draft thing", "opened": "2026-11-10T00:00:00Z",
                                       "draft": True}])
        self.assertEqual(eng["bugs"], [{"number": 5, "title": "Crash", "opened": "2026-11-01T00:00:00Z",
                                        "labels": ["P1"]}])
        self.assertEqual(eng["open_issues"], 74)


def numbers():
    days = [D(2026, 11, 4) + datetime.timedelta(days=i) for i in range(15)]
    store_days = [D(2026, 10, 21) + datetime.timedelta(days=i) for i in range(28)]
    store = [{"day": d.isoformat(), "downloads": 5 if d < D(2026, 11, 10) else 12, "downloads_ios": 0,
              "downloads_mac": 0, "trials": 1, "pro": 1 if d.day % 2 else 0, "pro_codes": 0, "packs": 0,
              "proceeds_usd": 3.5 if d.day % 2 else 0.0, "unconverted": {}} for d in store_days]
    return {
        "collected_at": "2026-11-18T15:27+00:00", "today": "2026-11-18",
        "site": {"daily": [{"day": d.isoformat(), "visitors": 10 if d < D(2026, 11, 10) else 100,
                            "facebook": 0 if d < D(2026, 11, 10) else 80} for d in days],
                 "sources": [{"source": "Facebook", "campaign": "fbad-x32", "visitors": 300},
                             {"source": "ChatGPT", "campaign": "", "visitors": 40},
                             {"source": "Direct", "campaign": "", "visitors": 20}],
                 "app_store_clicks": 90},
        "usage": [{"event": "take_started", "people": 22, "times": 54}],
        "store": {"daily": store, "first": "2026-11-04", "last": "2026-11-17", "redownloads": 116, "updates": 308,
                  "countries": {"US": 78, "GB": 8},
                  "total": {"downloads": 141, "downloads_ios": 138, "downloads_mac": 3, "trials": 27, "pro": 11,
                            "pro_codes": 2, "packs": 0, "proceeds_usd": 48.1, "unconverted": {"XYZ": 5.0}}},
        "testflight": {
            "store_versions": [{"platform": "MAC_OS", "version": "1.1.21", "state": "PREPARE_FOR_SUBMISSION"},
                               {"platform": "IOS", "version": "1.1.21", "state": "READY_FOR_SALE"}],
            "beta_review": [{"version": "1.2.14", "build": "65.1", "platform": "IOS", "review": "WAITING_FOR_REVIEW",
                             "processing": "VALID"}],
            "testers": {"installed": 49, "accepted": 4, "revoked": 1}, "reviews": [],
            "feedback": {"total": 2, "mine": 1, "others": [{"date": "2026-11-14T17:24", "platform": "IOS",
                                                             "build": "61.1", "comment": "<b>No</b> Drive copy"}]},
            "crashes": 0, "diagnostics": [{"version": "1.1.21", "signatures": [
                {"type": "DISK_WRITES", "weight": 94.0, "signature": "StemWriter"}]}]},
    }


ADS = {"read_at": "2026-11-17T17:46+00:00", "range": "Nov 3 – 16, 2026", "start": "2026-11-10", "budget": 60,
       "ads": [{"name": "Ad A, XR18 still", "tag": "fbad-xr18", "spent": 27.57, "impressions": 3748, "reach": 3241,
                "clicks": 236},
               {"name": "Ad B, X32 still", "tag": "fbad-x32", "spent": 26.32, "impressions": 3482, "reach": 3224,
                "clicks": 351}],
       "notices": ["Both ads end Nov 18."]}


class RenderTests(unittest.TestCase):
    def test_renders_the_summary_and_every_section(self):
        page = nr.render(numbers(), ADS, {"read_at": "2026-11-18T15:27+00:00", "app": [], "web": []},
                         {"price_check": {"label": "Nov 20 check", "needs": 0.055},
                          "sections": [{"title": "Dante", "src": "#1234", "points": ["Planned price: $19.99."]}],
                          "needs_you": [{"tag": "Mac", "level": "warn", "text": "Record a Mac Take."}],
                          "feedback_notes": {"2026-11-14T17:24": "Fixed in 1.2.13."}})
        for text in ("<title>ShowRecorder Numbers</title>", ">141<", "138 iPhone/iPad, 3 Mac", "from 27 trials",
                     "$48.10", "$53.89", ">7.8%<", "Nov 20 check needs ≥ 5.5%", "Ad B, X32 still is the better ad",
                     "10.1%", "Dante", "Record a Mac Take.", "Fixed in 1.2.13.", "1.2.14 (65.1)",
                     "Waiting for review", "Mac 1.1.21 is “Prepare for submission”", "XYZ 5.00",
                     "averaged <strong>100</strong> visitors a day, against 10 the week before", "<th>14 days</th>"):
            self.assertIn(text, page)

    def test_compares_downloads_in_the_week_from_the_ads_start_with_the_week_before(self):
        page = nr.render(numbers(), ADS)
        self.assertIn("Downloads were <strong>84</strong> in the 7 days from Nov 10, against 35", page)
        self.assertIn("about <strong>$1.10 per extra download</strong>", page)

    def test_escapes_tester_text(self):
        page = nr.render(numbers())
        self.assertIn("&lt;b&gt;No&lt;/b&gt; Drive copy", page)
        self.assertNotIn("<b>No</b>", page)

    def test_lists_threads_waiting_on_a_reply_and_puts_them_in_needs_you(self):
        n = numbers()
        n["support"] = {"waiting": [{"id": 26, "inbox": "ShowRecorder", "subject": "<i>USB</i> error", "status": "open",
                                     "since": "2026-11-16T16:37+00:00"}],
                        "new": [{"inbox": "ShowRecorder", "threads": 3, "answered": 2}]}
        page = nr.render(n)
        self.assertIn("<h2>Support</h2>", page)
        self.assertIn("#26", page)
        self.assertIn("&lt;i&gt;USB&lt;/i&gt; error", page)
        self.assertIn("Nov 16, 11:37 ET", page)
        self.assertIn("2 days", page)
        self.assertIn("3 new threads in ShowRecorder, 2 answered", page)
        self.assertIn("Reply to support thread #26", page)

    def test_shows_ci_uploads_prs_and_bugs_and_flags_a_failing_branch(self):
        n = numbers()
        n["engineering"] = {
            "ci": [{"branch": "main", "workflow": "CI", "result": "failure", "at": "2026-11-18T14:00:00Z",
                    "title": "<b>Break</b>", "url": "https://github.com/x/y/actions/runs/1"},
                   {"branch": "release/1.2", "workflow": "CI", "result": "success", "at": "2026-11-17T14:00:00Z",
                    "title": "Fix", "url": "https://github.com/x/y/actions/runs/2"}],
            "uploads": [{"tag": "v1.2.14", "result": "success", "at": "2026-11-18T00:42:02Z"}],
            "prs": [{"number": 9, "title": "Draft thing", "opened": "2026-11-10T00:00:00Z", "draft": True}],
            "bugs": [{"number": 5, "title": "Crash", "opened": "2026-11-01T00:00:00Z", "labels": ["P1"]}],
            "open_issues": 74}
        page = nr.render(n)
        self.assertIn("<h2>Engineering</h2>", page)
        self.assertIn("&lt;b&gt;Break&lt;/b&gt;", page)
        self.assertIn("v1.2.14", page)
        self.assertIn("#9 Draft thing (draft, open 8 days)", page)
        self.assertIn("#5 Crash (P1, open 17 days)", page)
        self.assertIn("74 open issues, 1 labeled bug.", page)
        self.assertIn("CI is failing on main", page)
        self.assertIn("Engineering not read", nr.render(numbers()))

    def test_shows_apple_ads_with_credit_left_and_keywords(self):
        apple = {"read_at": "2026-11-22T16:06+00:00", "range": "Nov 22 – 23, 2026 (UTC)", "start": "2026-11-22",
                 "credit": 100, "campaigns": [{"name": "SR Search US", "status": "Running", "daily_budget": 10,
                                               "spent": 12.5, "impressions": 400, "taps": 20, "installs": 5}],
                 "keywords": [{"text": "multitrack recorder", "spent": 6.0, "taps": 9, "installs": 3},
                              {"text": "<x>", "spent": 0.0, "taps": 0, "installs": 0}]}
        page = nr.render(numbers(), apple_ads=apple)
        self.assertIn("<h2>Apple Ads</h2>", page)
        self.assertIn("$12.50", page)
        self.assertIn("$87.50 of the $100.00 credit left", page)
        self.assertIn("5.0%", page)  # taps per impression
        self.assertIn("$2.50", page)  # per install
        self.assertIn("multitrack recorder", page)
        self.assertIn("&lt;x&gt;", page)
        self.assertIn("UTC", page)
        self.assertNotIn("<h2>Apple Ads</h2>", nr.render(numbers()))

    def test_says_when_nothing_waits_and_when_support_wasnt_read(self):
        n = numbers()
        n["support"] = {"waiting": [], "new": []}
        self.assertIn("Nothing is waiting on a reply.", nr.render(n))
        self.assertIn("Chatwoot not read", nr.render(numbers()))

    def test_leaves_out_the_ads_and_glitchtip_when_not_read(self):
        page = nr.render(numbers())
        self.assertNotIn("<h2>Facebook ads</h2>", page)
        self.assertIn("GlitchTip not read", page)
        self.assertIn("Site visitors, the last 7 complete days", page)


if __name__ == "__main__":
    unittest.main()
