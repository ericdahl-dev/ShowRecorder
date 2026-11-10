#!/usr/bin/env python3
"""Tests for post_tracker.py: reading the post log and joining it with site visits. No network, no keys.
Run: python3 scripts/test_post_tracker.py"""
import os, sys, tempfile, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import post_tracker as pt

LOG = """campaign,kind,group,members,posted,post,status,likes,comments,checked,url
xr18-group-beta-1-2,Group post,XR18/MR18 users tips and tricks,25400,2026-11-09,1.2 beta update,Up,12,4,2026-11-10,https://www.facebook.com/groups/458780207620383/
x32-group-beta-1-2,Group post,Behringer X32 Professional Users Forum,84500,,X32 tester call,Waiting on 1.2.10 beta review,,,,https://www.facebook.com/groups/716448431752719/
"""


def write_log(text):
    f = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False)
    f.write(text)
    f.close()
    return f.name


class LoadPostsTests(unittest.TestCase):
    def test_counts_are_numbers_and_blanks_are_none(self):
        posts = pt.load_posts(write_log(LOG))
        self.assertEqual(posts[0]["likes"], 12)
        self.assertEqual(posts[0]["members"], 25400)
        self.assertIsNone(posts[1]["likes"])
        self.assertIsNone(posts[1]["posted"])
        self.assertEqual(posts[1]["status"], "Waiting on 1.2.10 beta review")


class BoardTests(unittest.TestCase):
    def test_each_post_gets_its_campaign_visits_and_unposted_ones_get_zero(self):
        posts = pt.load_posts(write_log(LOG))
        visits = [{"campaign": "xr18-group-beta-1-2", "people": 18, "pageviews": 20, "joinBeta": 2, "appStore": 0}]
        board = {r["campaign"]: r for r in pt.board(posts, visits)}
        self.assertEqual((board["xr18-group-beta-1-2"]["people"], board["xr18-group-beta-1-2"]["joinBeta"]), (18, 2))
        self.assertEqual(board["x32-group-beta-1-2"]["people"], 0)

    def test_a_campaign_with_visits_but_no_log_row_still_shows(self):
        board = pt.board([], [{"campaign": "fb-page", "people": 2, "pageviews": 2, "joinBeta": 0, "appStore": 0}])
        self.assertEqual([(r["campaign"], r["status"]) for r in board], [("fb-page", "Not in the log")])

    def test_most_people_first(self):
        posts = pt.load_posts(write_log(LOG))
        visits = [{"campaign": "x32-group-beta-1-2", "people": 30, "pageviews": 30, "joinBeta": 0, "appStore": 0},
                  {"campaign": "xr18-group-beta-1-2", "people": 18, "pageviews": 20, "joinBeta": 2, "appStore": 0}]
        self.assertEqual([r["campaign"] for r in pt.board(posts, visits)], ["x32-group-beta-1-2", "xr18-group-beta-1-2"])


class TableTests(unittest.TestCase):
    def test_table_names_the_group_and_its_numbers(self):
        posts = pt.load_posts(write_log(LOG))
        text = pt.table(pt.board(posts, [{"campaign": "xr18-group-beta-1-2", "people": 18, "pageviews": 20, "joinBeta": 2, "appStore": 0}]))
        line = next(l for l in text.splitlines() if "XR18/MR18" in l)
        self.assertIn("18", line)
        self.assertIn("12", line)  # likes


if __name__ == "__main__":
    unittest.main()
