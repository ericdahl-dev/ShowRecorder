#!/usr/bin/env python3
"""Tests for asc_stats.py: turning App Store sales reports into totals. No network, no keys.
Run: python3 scripts/test_asc_stats.py"""
import os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_stats

COLUMNS = ["SKU", "Parent Identifier", "Product Type Identifier", "Units", "Developer Proceeds",
           "Country Code", "Currency of Proceeds", "Apple Identifier"]


def report(*rows):
    """A daily sales report as Apple sends it (tab-separated), one row per dict."""
    lines = ["\t".join(COLUMNS)]
    for row in rows:
        full = {"SKU": "showrecorder", "Parent Identifier": " ", "Units": "1", "Developer Proceeds": "0",
                "Country Code": "US", "Currency of Proceeds": "USD", "Apple Identifier": "app", **row}
        lines.append("\t".join(full[c] for c in COLUMNS))
    return "\n".join(lines) + "\n"


class SummarizeTests(unittest.TestCase):
    def test_counts_downloads_of_this_app_only(self):
        reports = {"2026-11-01": report(
            {"Product Type Identifier": "1F", "Units": "3"},
            {"Product Type Identifier": "1", "Units": "2"},
            {"Product Type Identifier": "1F", "Units": "9", "SKU": "other", "Apple Identifier": "otherapp"},
        )}
        summary = asc_stats.summarize(reports, app_id="app", sku="showrecorder")
        self.assertEqual(summary.units["downloads"], 5)

    def test_counts_pro_purchases_and_their_proceeds_by_currency(self):
        pro = {"Product Type Identifier": "IA1", "SKU": "pro", "Apple Identifier": "proid",
               "Parent Identifier": "showrecorder"}
        reports = {
            "2026-11-01": report({**pro, "Units": "2", "Developer Proceeds": "3.50"},
                                 {**pro, "Currency of Proceeds": "GBP", "Developer Proceeds": "2.35"}),
            "2026-11-02": report({**pro, "Developer Proceeds": "3.50"},
                                 {**pro, "Parent Identifier": "otherapp", "Developer Proceeds": "9"}),
        }
        summary = asc_stats.summarize(reports, app_id="app", sku="showrecorder")
        self.assertEqual(summary.units["pro"], 4)
        self.assertEqual(summary.proceeds, {"USD": 10.5, "GBP": 2.35})

    def test_counts_the_free_trial_apart_from_pro(self):
        trial = {"Product Type Identifier": "IA1", "SKU": "dev.ericdahl.ShowRecorder.trial", "Apple Identifier": "trialid",
                 "Parent Identifier": "showrecorder", "Developer Proceeds": "0"}
        pro = {"Product Type Identifier": "IA1", "SKU": "dev.ericdahl.ShowRecorder.pro", "Apple Identifier": "proid",
               "Parent Identifier": "showrecorder", "Developer Proceeds": "4.24"}
        reports = {"2026-11-03": report(trial, trial, {**trial, "Currency of Proceeds": "GBP"}, pro)}
        summary = asc_stats.summarize(reports, app_id="app", sku="showrecorder")
        self.assertEqual(summary.units["trials"], 3)
        self.assertEqual(summary.units["pro"], 1)
        self.assertEqual(summary.proceeds, {"USD": 4.24})

    def test_sorts_iphone_and_mac_rows_into_downloads_updates_and_redownloads(self):
        reports = {"2026-11-01": report(
            *({"Product Type Identifier": kind} for kind in ("1F", "F1", "7F", "7", "F7", "3F", "F3")),
            {"Product Type Identifier": "FI1", "SKU": "pro", "Apple Identifier": "proid", "Parent Identifier": "showrecorder"},
        )}
        summary = asc_stats.summarize(reports, app_id="app", sku="showrecorder")
        self.assertEqual(dict(summary.units), {"downloads": 2, "updates": 3, "redownloads": 2, "pro": 1})

    def test_breaks_downloads_down_by_day_and_country(self):
        reports = {
            "2026-11-02": report({"Product Type Identifier": "1F", "Units": "2", "Country Code": "GB"}),
            "2026-11-01": report({"Product Type Identifier": "1F"}, {"Product Type Identifier": "F1", "Country Code": "GB"},
                                 {"Product Type Identifier": "7F", "Units": "5"}),
        }
        summary = asc_stats.summarize(reports, app_id="app", sku="showrecorder")
        self.assertEqual(summary.downloads_by_day, {"2026-11-01": 2, "2026-11-02": 2})
        self.assertEqual(summary.downloads_by_country.most_common(), [("GB", 3), ("US", 1)])


if __name__ == "__main__":
    unittest.main()
