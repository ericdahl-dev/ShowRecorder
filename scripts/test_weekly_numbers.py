#!/usr/bin/env python3
"""Tests for weekly_numbers.py: the weekly numbers table, its deltas and its flags. No network, no keys.
Run: python3 scripts/test_weekly_numbers.py"""
import datetime, os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weekly_numbers as wn
from test_asc_stats import report  # a daily sales report as Apple sends it

D = datetime.date


class WindowTests(unittest.TestCase):
    def test_last_week_prior_week_and_since_launch_end_yesterday(self):
        last, prior, launch = wn.windows(D(2026, 11, 7))
        self.assertEqual((last.start, last.end), (D(2026, 10, 31), D(2026, 11, 6)))
        self.assertEqual((prior.start, prior.end), (D(2026, 10, 24), D(2026, 10, 30)))
        self.assertEqual((launch.start, launch.end), (D(2026, 10, 28), D(2026, 11, 6)))
        self.assertEqual(last.label, "Oct 31-Nov 6")


class ChangeFlagTests(unittest.TestCase):
    def test_flags_a_change_of_2x_or_more_either_way(self):
        self.assertEqual(wn.change_flag(10, 5), "2x up")
        self.assertEqual(wn.change_flag(31, 10), "3.1x up")
        self.assertEqual(wn.change_flag(5, 10), "2x down")
        self.assertEqual(wn.change_flag(2, 9), "4.5x down")

    def test_leaves_smaller_changes_unflagged(self):
        self.assertEqual(wn.change_flag(19, 10), "")
        self.assertEqual(wn.change_flag(6, 10), "")
        self.assertEqual(wn.change_flag(0, 0), "")

    def test_marks_a_start_from_zero_and_a_drop_to_zero(self):
        self.assertEqual(wn.change_flag(4, 0), "new")
        self.assertEqual(wn.change_flag(0, 4), "to 0")

    def test_no_flag_when_a_value_is_missing(self):
        self.assertEqual(wn.change_flag(None, 4), "")
        self.assertEqual(wn.change_flag(4, None), "")


class SourceTests(unittest.TestCase):
    def test_utm_source_wins_and_chatgpt_is_its_own_source(self):
        self.assertEqual(wn.source_of("chatgpt.com", "$direct"), "ChatGPT")
        self.assertEqual(wn.source_of(None, "chatgpt.com"), "ChatGPT")
        self.assertEqual(wn.source_of("reddit", "$direct"), "reddit")
        self.assertEqual(wn.source_of("Facebook", "$direct"), "Facebook")

    def test_tagged_facebook_links_and_facebook_referrers_are_one_source(self):
        self.assertEqual(wn.source_of("facebook", "$direct"), "Facebook")
        self.assertEqual(wn.source_of(None, "lm.facebook.com"), "Facebook")

    def test_referrers_fold_into_named_sources(self):
        for ref in ("facebook.com", "l.facebook.com", "lm.facebook.com", "en-gb.facebook.com", "m.facebook.com"):
            self.assertEqual(wn.source_of(None, ref), "Facebook")
        for ref in ("www.google.com", "duckduckgo.com", "www.bing.com"):
            self.assertEqual(wn.source_of(None, ref), "Search")
        self.assertEqual(wn.source_of(None, "$direct"), "Direct")
        self.assertEqual(wn.source_of(None, None), "Direct")
        self.assertEqual(wn.source_of(None, "showrecorder.app"), "Direct")
        self.assertEqual(wn.source_of(None, "github.com"), "github.com")

    def test_counts_each_visitor_once_by_their_first_source_in_the_window(self):
        rows = [  # day, visitor, utm_source, referring domain
            (D(2026, 11, 1), "a", None, "facebook.com"),
            (D(2026, 11, 2), "a", None, "$direct"),
            (D(2026, 11, 2), "b", "chatgpt.com", "$direct"),
            (D(2026, 10, 25), "c", None, "www.google.com"),
            (D(2026, 10, 30), "a", None, "www.google.com"),
        ]
        last, prior, _ = wn.windows(D(2026, 11, 7))
        self.assertEqual(wn.visitors_by_source(rows, last), {"Facebook": 1, "ChatGPT": 1})
        self.assertEqual(wn.visitors_by_source(rows, prior), {"Search": 2})


class PageTests(unittest.TestCase):
    def test_counts_unique_visitors_per_guide_page_in_the_window(self):
        rows = [  # day, path, visitor
            (D(2026, 11, 1), "/guides/record/x32", "a"),
            (D(2026, 11, 2), "/guides/record/x32", "a"),
            (D(2026, 11, 2), "/guides/record/x32", "b"),
            (D(2026, 11, 2), "/mixers/xr18", "b"),
            (D(2026, 11, 2), "/docs/pricing", "b"),
            (D(2026, 10, 29), "/mixers/xr18", "c"),
        ]
        last, _, _ = wn.windows(D(2026, 11, 7))
        self.assertEqual(wn.guide_page_visitors(rows, last), {"/guides/record/x32": 2, "/mixers/xr18": 1})


PRO = {"Product Type Identifier": "IA1", "SKU": "dev.ericdahl.ShowRecorder.pro", "Apple Identifier": "proid",
       "Parent Identifier": "showrecorder", "Developer Proceeds": "4.24"}
TRIAL = {**PRO, "SKU": "dev.ericdahl.ShowRecorder.trial", "Customer Price": "0.00", "Developer Proceeds": "0.00"}
DOWNLOAD = {"Product Type Identifier": "1F", "Customer Price": "0.00"}


class AppStoreTests(unittest.TestCase):
    def setUp(self):
        self.last, self.prior, self.launch = wn.windows(D(2026, 11, 7))

    def numbers(self, reports, window, rates=None):
        return wn.app_store_numbers(reports, window, app_id="app", sku="showrecorder", usd_rates=rates or {"USD": 1})

    def test_sums_only_the_days_in_the_window(self):
        reports = {
            "2026-10-30": report({**DOWNLOAD, "Units": "9"}),
            "2026-10-31": report({**DOWNLOAD, "Units": "3"}, {**DOWNLOAD, "Device": "Desktop"}, TRIAL, TRIAL, PRO),
            "2026-11-05": report({**DOWNLOAD, "Units": "6"}, PRO),
        }
        week = self.numbers(reports, self.last)
        self.assertEqual((week["downloads_ios"], week["downloads_mac"], week["downloads"]), (9, 1, 10))
        self.assertEqual((week["trials"], week["pro"]), (2, 2))
        self.assertEqual(self.numbers(reports, self.prior)["downloads"], 9)
        self.assertEqual(self.numbers(reports, self.launch)["downloads"], 19)

    def test_converts_proceeds_to_dollars_and_derives_revenue_per_download_and_download_to_pro(self):
        reports = {"2026-11-01": report(
            {**DOWNLOAD, "Units": "20"}, PRO,
            {**PRO, "Currency of Proceeds": "GBP", "Developer Proceeds": "3.52"},
            {**PRO, "Currency of Proceeds": "PLN", "Developer Proceeds": "17.27"},
        )}
        week = self.numbers(reports, self.last, rates={"USD": 1, "GBP": 0.8, "PLN": 4.0})
        self.assertEqual(week["pro"], 3)
        self.assertAlmostEqual(week["proceeds_usd"], 4.24 + 4.40 + 4.3175)
        self.assertEqual(week["unconverted"], {})
        self.assertAlmostEqual(week["revenue_per_download"], week["proceeds_usd"] / 20)
        self.assertAlmostEqual(week["download_to_pro"], 3 / 20)

    def test_keeps_proceeds_it_has_no_rate_for_apart(self):
        reports = {"2026-11-01": report(DOWNLOAD, {**PRO, "Currency of Proceeds": "COP", "Developer Proceeds": "17785.71"})}
        week = self.numbers(reports, self.last)
        self.assertEqual(week["proceeds_usd"], 0)
        self.assertEqual(week["unconverted"], {"COP": 17785.71})

    def test_no_rates_without_downloads(self):
        week = self.numbers({"2026-11-06": report(TRIAL)}, self.last)  # a published day with no downloads
        self.assertEqual(week["downloads"], 0)
        self.assertIsNone(week["revenue_per_download"])
        self.assertIsNone(week["download_to_pro"])


class UsageTests(unittest.TestCase):
    def test_counts_take_events_and_the_devices_that_sent_them(self):
        rows = [  # day, event, device
            (D(2026, 11, 3), "take_started", "phone1"),
            (D(2026, 11, 3), "take_stopped", "phone1"),
            (D(2026, 11, 6), "take_started", "phone1"),
            (D(2026, 11, 6), "take_started", "phone2"),
            (D(2026, 10, 29), "take_started", "phone3"),
        ]
        last, _, _ = wn.windows(D(2026, 11, 7))
        self.assertEqual(wn.usage_numbers(rows, last), {"take_started": 3, "take_stopped": 1, "devices": 2})

    def test_leaves_out_internal_installs(self):
        eric = next(iter(wn.INTERNAL_INSTALLS))
        rows = [  # day, event, device
            (D(2026, 11, 6), "take_started", eric),
            (D(2026, 11, 6), "take_stopped", eric),
            (D(2026, 11, 6), "take_started", "tester"),
        ]
        last, _, _ = wn.windows(D(2026, 11, 7))
        self.assertEqual(wn.usage_numbers(rows, last), {"take_started": 1, "take_stopped": 0, "devices": 1})


def store(**numbers):
    base = {"downloads": 0, "downloads_ios": 0, "downloads_mac": 0, "trials": 0, "pro": 0, "pro_codes": 0, "packs": 0,
            "proceeds_usd": 0.0, "unconverted": {}, "revenue_per_download": None, "download_to_pro": None,
            "report_days": []}
    return {**base, **numbers}


def site(**numbers):
    return {"visitors": 0, "sources": {}, "pages": {}, "app_store_clicks": 0, **numbers}


USAGE = {"take_started": 0, "take_stopped": 0, "devices": 0}


class TableTests(unittest.TestCase):
    def setUp(self):
        self.windows = wn.windows(D(2026, 11, 7))

    def table(self, sites, stores, usages=(USAGE, USAGE, USAGE)):
        return wn.table(self.windows, list(sites), list(stores), list(usages))

    def row(self, text, label):
        line = next(line for line in text.splitlines() if line.startswith(f"| {label} |"))
        return [cell.strip() for cell in line.strip("|").split("|")]

    def test_header_names_each_window(self):
        text = self.table([site()] * 3, [store()] * 3)
        self.assertEqual(text.splitlines()[0],
                         "| | Last 7 days (Oct 31-Nov 6) | Prior 7 days (Oct 24-30) | Since launch (Oct 28-Nov 6) | Flag |")

    def test_each_row_shows_the_three_windows_and_flags_a_2x_change(self):
        stores = [store(downloads_ios=30, pro=3, proceeds_usd=12.96, revenue_per_download=0.432, download_to_pro=0.1),
                  store(downloads_ios=12, pro=2, proceeds_usd=8.48, revenue_per_download=0.7067, download_to_pro=1 / 6),
                  store(downloads_ios=50, pro=6)]
        text = self.table([site()] * 3, stores)
        self.assertEqual(self.row(text, "Downloads, iPhone and iPad"), ["Downloads, iPhone and iPad", "30", "12", "50", "2.5x up"])
        self.assertEqual(self.row(text, "Pro sold"), ["Pro sold", "3", "2", "6", ""])
        self.assertEqual(self.row(text, "Proceeds (USD)"), ["Proceeds (USD)", "$12.96", "$8.48", "$0.00", ""])
        self.assertEqual(self.row(text, "Revenue per download"), ["Revenue per download", "$0.43", "$0.71", "-", ""])
        self.assertEqual(self.row(text, "Download-to-Pro"), ["Download-to-Pro", "10.0%", "16.7%", "-", ""])

    def test_lists_every_source_with_chatgpt_always_shown_most_visitors_first(self):
        sites = [site(visitors=9, sources={"Facebook": 6, "Direct": 3}),
                 site(visitors=4, sources={"Direct": 4}),
                 site(visitors=20, sources={"Direct": 9, "Facebook": 11})]
        text = self.table(sites, [store()] * 3)
        labels = [line.split("|")[1].strip() for line in text.splitlines()]
        sources = [label for label in labels if label.startswith("from ")]
        self.assertEqual(sources, ["from Facebook", "from Direct", "from ChatGPT"])
        self.assertEqual(self.row(text, "from Facebook"), ["from Facebook", "6", "0", "11", "new"])

    def test_shows_the_top_five_guide_pages_since_launch(self):
        pages = {f"/mixers/m{n}": n for n in range(1, 8)}
        text = self.table([site(pages={"/mixers/m1": 4}), site(), site(pages=pages)], [store()] * 3)
        shown = [line.split("|")[1].strip() for line in text.splitlines() if "/mixers/" in line]
        self.assertEqual(shown, [f"`/mixers/m{n}`" for n in (7, 6, 5, 4, 3)])

    def test_has_the_take_events(self):
        usages = [{"take_started": 4, "take_stopped": 4, "devices": 1}, USAGE, USAGE]
        text = self.table([site()] * 3, [store()] * 3, usages)
        self.assertEqual(self.row(text, "take_started"), ["take_started", "4", "0", "0", "new"])


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.windows = wn.windows(D(2026, 11, 7))

    def notes(self, stores, sites=None, usages=(USAGE, USAGE, USAGE)):
        return "\n".join(wn.notes(self.windows, list(sites or [site()] * 3), list(stores), list(usages)))

    def test_names_each_2x_change(self):
        stores = [store(downloads_ios=30, trials=2), store(downloads_ios=12, trials=8), store()]
        text = self.notes(stores)
        self.assertIn("Downloads, iPhone and iPad 2.5x up", text)
        self.assertIn("Trials started 4x down", text)

    def test_price_step_check_passes_at_or_above_5_5_percent(self):
        stores = [store(downloads=100, download_to_pro=0.06), store(), store(downloads=200, download_to_pro=0.055)]
        text = self.notes(stores)
        self.assertIn("Nov 20 price step", text)
        self.assertIn("5.5%", text)
        self.assertIn("last 7 days 6.0% (holds)", text)
        self.assertIn("since launch 5.5% (holds)", text)

    def test_price_step_check_fails_below_5_5_percent(self):
        stores = [store(downloads=100, download_to_pro=0.05), store(), store(downloads=100, download_to_pro=None)]
        text = self.notes(stores)
        self.assertIn("last 7 days 5.0% (below)", text)
        self.assertIn("since launch - (no downloads)", text)

    def test_says_usage_is_testflight_only(self):
        self.assertIn("TestFlight", self.notes([store()] * 3))

    def test_says_when_apple_has_not_published_the_last_day(self):
        stores = [store(report_days=["2026-10-31", "2026-11-05"]), store(), store()]
        self.assertIn("App Store reports run through Nov 5", self.notes(stores))
        stores = [store(report_days=["2026-11-06"]), store(), store()]
        self.assertNotIn("run through", self.notes(stores))

    def test_says_when_the_prior_week_starts_before_launch(self):
        self.assertIn("Prior 7 days include 4 days before launch", self.notes([store()] * 3))
        later = wn.windows(D(2026, 11, 14))
        text = "\n".join(wn.notes(later, [site()] * 3, [store()] * 3, [USAGE] * 3))
        self.assertNotIn("before launch", text)

    def test_lists_proceeds_with_no_exchange_rate(self):
        stores = [store(unconverted={"COP": 17785.71}), store(), store(unconverted={"COP": 17785.71})]
        self.assertIn("COP 17,785.71", self.notes(stores))


class DailyTests(unittest.TestCase):
    """DAYS=1: the daily email, yesterday beside the day before and the total since launch."""
    def setUp(self):
        self.windows = wn.windows(D(2026, 11, 11), days=1)

    def test_yesterday_the_day_before_and_since_launch(self):
        day, before, launch = self.windows
        self.assertEqual((day.start, day.end), (D(2026, 11, 10), D(2026, 11, 10)))
        self.assertEqual((before.start, before.end), (D(2026, 11, 9), D(2026, 11, 9)))
        self.assertEqual((launch.start, launch.end), (D(2026, 10, 28), D(2026, 11, 10)))
        self.assertEqual(day.label, "Nov 10")

    def test_header_names_the_days(self):
        text = wn.table(self.windows, [site()] * 3, [store()] * 3, [USAGE] * 3)
        self.assertEqual(text.splitlines()[0],
                         "| | Yesterday (Nov 10) | Day before (Nov 9) | Since launch (Oct 28-Nov 10) | Flag |")

    def test_notes_compare_with_the_day_before(self):
        stores = [store(downloads=10, download_to_pro=0.1), store(downloads=4), store()]
        text = "\n".join(wn.notes(self.windows, [site()] * 3, stores, [USAGE] * 3))
        self.assertIn("2x or more against the day before:", text)
        self.assertIn("Now: yesterday 10.0% (holds)", text)
        self.assertNotIn("7 days", text)

    def test_app_store_shows_a_dash_not_zero_before_apple_publishes_the_day(self):
        window = self.windows[0]
        numbers = wn.app_store_numbers({}, window, app_id="app", sku="showrecorder", usd_rates={"USD": 1})
        self.assertIsNone(numbers["downloads_ios"])
        self.assertIsNone(numbers["proceeds_usd"])
        self.assertEqual(numbers["report_days"], [])
        stores = [numbers, store(downloads_ios=7, pro=1), store()]
        text = wn.table(self.windows, [site()] * 3, stores, [USAGE] * 3)
        line = next(l for l in text.splitlines() if l.startswith("| Downloads, iPhone and iPad |"))
        self.assertEqual([c.strip() for c in line.strip("|").split("|")], ["Downloads, iPhone and iPad", "-", "7", "0", ""])
        notes = "\n".join(wn.notes(self.windows, [site()] * 3, stores, [USAGE] * 3))
        self.assertIn("yesterday - (no report yet)", notes)
        self.assertNotIn("Downloads, iPhone and iPad to 0", notes)

    def test_title_says_daily(self):
        text = wn.report(D(2026, 11, 11), [site()] * 3, [store()] * 3, [USAGE] * 3, days=1)
        self.assertTrue(text.startswith("# ShowRecorder daily numbers, 2026-11-11\n"))
        self.assertIn("Yesterday (Nov 10)", text)

    def test_weekly_title_unchanged(self):
        text = wn.report(D(2026, 11, 9), [site()] * 3, [store()] * 3, [USAGE] * 3)
        self.assertTrue(text.startswith("# ShowRecorder weekly numbers, 2026-11-09\n"))


class AppStoreClickTests(unittest.TestCase):
    def test_counts_the_mixer_page_button_as_the_site_sends_it(self):
        # mixer_page_cta_clicked carries destination 'app_store', not a URL (38 people missed, 2026-11-11)
        self.assertIn("event = 'app_store_clicked'", wn.APP_STORE_CLICK)
        self.assertIn("properties.destination) = 'app_store'", wn.APP_STORE_CLICK)


if __name__ == "__main__":
    unittest.main()
