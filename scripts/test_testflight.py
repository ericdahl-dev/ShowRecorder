#!/usr/bin/env python3
"""Tests for the TestFlight scripts: internal-only tags (testflight_notes.py) and promoting them to External
testers later (testflight_promote.py), against a fake App Store Connect API. No network, no keys.
Run: python3 scripts/test_testflight.py"""
import os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testflight_notes as notes
import testflight_promote as promote


class FakeAPI:
    """App Store Connect in memory: one app, its beta groups, builds by platform and version, and what was asked."""

    def __init__(self, builds=None, groups=None):
        self.calls = []
        self.groups = groups or [
            {"id": "team", "attributes": {"name": "Team", "isInternalGroup": True}},
            {"id": "ext", "attributes": {"name": "External", "isInternalGroup": False}},
        ]
        self.builds = builds or {}          # (platform, version) -> [build, newest first]
        self.build_groups = {}              # build id -> set of group ids
        self.submitted = {}                 # build id -> beta review state

    def call(self, method, path, body=None, query=None):
        self.calls.append((method, path))
        if method == "GET" and path == "/apps":
            return {"data": [{"id": "app"}]}
        if method == "GET" and path == "/apps/app/betaGroups":
            return {"data": self.groups}
        if method == "GET" and path == "/builds":
            key = (query["filter[preReleaseVersion.platform]"], query["filter[preReleaseVersion.version]"])
            return {"data": self.builds.get(key, [])}
        if method == "GET" and path == "/betaGroups":
            build = query["filter[builds]"]
            return {"data": [{"id": g} for g in sorted(self.build_groups.get(build, set()))]}
        if method == "GET" and path.endswith("/betaAppReviewSubmission"):
            build = path.split("/")[2]
            state = self.submitted.get(build)
            return {"data": {"id": "s-" + build, "attributes": {"betaReviewState": state}} if state else None}
        if method == "POST" and path.startswith("/betaGroups/") and path.endswith("/relationships/builds"):
            group = path.split("/")[2]
            if any(g["id"] == group and g["attributes"].get("hasAccessToAllBuilds") for g in self.groups):
                raise AssertionError(f"Apple refuses adding a build to {group}: it already gets every build")
            for item in body["data"]:
                self.build_groups.setdefault(item["id"], set()).add(group)
            return {}
        if method == "POST" and path == "/betaAppReviewSubmissions":
            self.submitted[body["data"]["relationships"]["build"]["data"]["id"]] = "WAITING_FOR_REVIEW"
            return {}
        return {"data": []}


def build(build_id, state="VALID", expired=False):
    return {"id": build_id, "attributes": {"processingState": state, "expired": expired}}


class InternalTagTests(unittest.TestCase):
    def test_marker_in_the_tag_message(self):
        self.assertTrue(notes.internal_tag("v1.1.3 [internal]: the watch app, for Eric's Take first"))
        self.assertTrue(notes.internal_tag("[Internal] real-time changes"))
        self.assertFalse(notes.internal_tag("v1.1.3: the watch app"))
        self.assertFalse(notes.internal_tag(""))

    def test_internal_build_goes_to_the_team_only(self):
        api = FakeAPI()
        notes.distribute(api, "app", "b1", internal=True)
        self.assertEqual(api.build_groups, {"b1": {"team"}})
        self.assertEqual(api.submitted, {}, "no Beta App Review for an internal-only tag")

    def test_normal_build_goes_to_external_and_review_as_before(self):
        api = FakeAPI()
        notes.distribute(api, "app", "b1", internal=False)
        self.assertEqual(api.build_groups, {"b1": {"ext"}})
        self.assertEqual(set(api.submitted), {"b1"})


class InternalGroupsTests(unittest.TestCase):
    def test_a_group_that_gets_every_build_is_left_alone(self):
        api = FakeAPI(groups=[
            {"id": "all", "attributes": {"name": "Everyone", "isInternalGroup": True, "hasAccessToAllBuilds": True}},
            {"id": "team", "attributes": {"name": "Team", "isInternalGroup": True}},
        ])
        notes.distribute(api, "app", "b1", internal=True)
        self.assertEqual(api.build_groups, {"b1": {"team"}})


class PromoteTests(unittest.TestCase):
    def test_promotes_the_newest_valid_build_on_each_platform(self):
        api = FakeAPI(builds={
            ("IOS", "1.1.3"): [build("ios-new"), build("ios-old")],
            ("MAC_OS", "1.1.3"): [build("mac-ok")],
        })
        promote.promote(api, "v1.1.3")
        self.assertEqual(api.build_groups, {"ios-new": {"ext"}, "mac-ok": {"ext"}})
        self.assertEqual(set(api.submitted), {"ios-new", "mac-ok"})

    def test_running_it_again_changes_nothing(self):
        api = FakeAPI(builds={("IOS", "1.1.3"): [build("ios")]})
        promote.promote(api, "v1.1.3")
        before = [c for c in api.calls if c[0] == "POST"]
        promote.promote(api, "v1.1.3")
        after = [c for c in api.calls if c[0] == "POST"]
        self.assertEqual(before, after, "no second add or submission")

    def test_a_platform_with_no_build_is_skipped(self):
        api = FakeAPI(builds={("IOS", "1.1.3"): [build("ios")]})
        report = promote.promote(api, "v1.1.3")
        self.assertIn("no build", report["MAC_OS"])
        self.assertEqual(set(api.submitted), {"ios"})

    def test_the_newest_build_still_processing_is_not_swapped_for_an_older_one(self):
        api = FakeAPI(builds={("IOS", "1.1.3"): [build("ios-rerun", "PROCESSING"), build("ios-first")]})
        report = promote.promote(api, "v1.1.3")
        self.assertIn("PROCESSING", report["IOS"])
        self.assertEqual(api.submitted, {})

    def test_an_expired_build_is_not_promoted(self):
        api = FakeAPI(builds={("IOS", "1.1.3"): [build("ios", expired=True)]})
        report = promote.promote(api, "v1.1.3")
        self.assertIn("expired", report["IOS"])
        self.assertEqual(api.submitted, {})

    def test_a_rejected_review_says_so(self):
        api = FakeAPI(builds={("IOS", "1.1.3"): [build("ios")]})
        api.submitted["ios"] = "REJECTED"
        report = promote.promote(api, "v1.1.3")
        self.assertIn("rejected", report["IOS"])

    def test_a_tag_that_isnt_a_version_is_refused(self):
        with self.assertRaises(ValueError):
            promote.promote(FakeAPI(), "main")


if __name__ == "__main__":
    unittest.main(verbosity=1)
