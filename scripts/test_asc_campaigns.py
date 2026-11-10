#!/usr/bin/env python3
"""Tests for asc_campaigns.py: reading Apple's App Downloads Detailed report and counting downloads per campaign.
No network, no keys. Run: python3 scripts/test_asc_campaigns.py"""
import os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_campaigns as ac

HEADER = ("Date\tApp Name\tApp Apple Identifier\tDownload Type\tApp Version\tDevice\tPlatform Version\tSource Type\t"
          "Source Info\tCampaign\tPage Type\tPage Title\tPre-Order\tTerritory\tCounts\n")


def report(*rows):
    """A report from (date, download type, campaign, counts) rows."""
    lines = [f"{d}\tShowRecorder\t6820213310\t{kind}\t1.1.19\tiPhone\tiOS 27.2\tWeb referrer\tshowrecorder.app\t{c}\t"
             f"Product page\tDefault product page\t\tUS\t{n}\n" for d, kind, c, n in rows]
    return HEADER + "".join(lines)


class DownloadsByDayTests(unittest.TestCase):
    def test_first_time_downloads_and_redownloads_are_counted_apart_per_day_and_campaign(self):
        text = report(("2026-11-09", "First-time download", "site-xr18", 2),
                      ("2026-11-09", "First-time download", "site-xr18", 1),
                      ("2026-11-09", "Redownload", "site-xr18", 1),
                      ("2026-11-10", "First-time download", "site-home", 1))
        days = ac.downloads_by_day([text])
        self.assertEqual(days[("2026-11-09", "site-xr18")], {"first": 3, "redownloads": 1})
        self.assertEqual(days[("2026-11-10", "site-home")], {"first": 1, "redownloads": 0})

    def test_downloads_without_a_campaign_are_listed_as_no_tag(self):
        days = ac.downloads_by_day([report(("2026-11-09", "First-time download", "", 4))])
        self.assertEqual(days, {("2026-11-09", ac.NO_TAG): {"first": 4, "redownloads": 0}})

    def test_updates_and_restores_are_not_downloads(self):
        text = report(("2026-11-09", "Auto-update", "site-x32", 9), ("2026-11-09", "Manual update", "site-x32", 2),
                      ("2026-11-09", "Restore", "site-x32", 1))
        self.assertEqual(ac.downloads_by_day([text]), {})


class TotalsTests(unittest.TestCase):
    def test_totals_add_up_each_campaign_over_all_days_with_the_most_first_time_downloads_first(self):
        days = {("2026-11-09", "site-home"): {"first": 1, "redownloads": 0},
                ("2026-11-09", "site-xr18"): {"first": 2, "redownloads": 1},
                ("2026-11-10", "site-xr18"): {"first": 1, "redownloads": 0}}
        self.assertEqual(ac.totals(days), [{"campaign": "site-xr18", "first": 3, "redownloads": 1},
                                           {"campaign": "site-home", "first": 1, "redownloads": 0}])


class RenderTests(unittest.TestCase):
    def test_no_reports_yet_says_so(self):
        text = ac.render({})
        self.assertIn("No campaign downloads yet", text)

    def test_report_lists_each_day_by_campaign_then_the_totals(self):
        days = {("2026-11-10", "site-home"): {"first": 1, "redownloads": 0},
                ("2026-11-09", "site-xr18"): {"first": 2, "redownloads": 1}}
        lines = ac.render(days).splitlines()
        day_lines = [line for line in lines if line.startswith("2026-")]
        self.assertEqual(day_lines, ["2026-11-09  site-xr18  first 2  redownloads 1",
                                     "2026-11-10  site-home  first 1  redownloads 0"])
        self.assertIn("site-xr18  first 2  redownloads 1", lines[lines.index("Totals:") + 1])


class JsonTests(unittest.TestCase):
    def test_json_has_one_row_per_day_and_campaign_in_date_order_plus_the_totals(self):
        days = {("2026-11-10", "site-home"): {"first": 1, "redownloads": 0},
                ("2026-11-09", "site-xr18"): {"first": 2, "redownloads": 1}}
        doc = ac.as_json(days)
        self.assertEqual(doc["days"], [{"date": "2026-11-09", "campaign": "site-xr18", "first": 2, "redownloads": 1},
                                       {"date": "2026-11-10", "campaign": "site-home", "first": 1, "redownloads": 0}])
        self.assertEqual(doc["totals"], ac.totals(days))


if __name__ == "__main__":
    unittest.main()
