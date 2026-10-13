#!/usr/bin/env python3
"""Sends an internal-only tag's builds on to external testers: for the tag's version, the newest processed iPhone
and Mac builds go to the external TestFlight group(s) and are submitted for Beta App Review. Run it after Eric's
Take on a real device (see docs/DEVELOPING.md, "Internal-only tags").

    python3 scripts/testflight_promote.py v1.1.3

Running it again changes nothing: a build already in a group isn't added again, and one already submitted isn't
submitted again. A platform with no processed build for the version is skipped and said so.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the release's App Store Connect key) and BUNDLE_ID
(dev.ericdahl.ShowRecorder by default). Prints no secret.
"""
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PLATFORMS = ("IOS", "MAC_OS")


def newest(api, app_id: str, version: str, platform: str):
    """The version's newest build on the platform (a re-run tag makes several), or None."""
    found = api.call("GET", "/builds", query={
        "filter[app]": app_id, "filter[preReleaseVersion.version]": version,
        "filter[preReleaseVersion.platform]": platform, "sort": "-uploadedDate", "limit": 1})["data"]
    return found[0] if found else None


def promote(api, tag: str) -> dict:
    """Returns what happened on each platform, in words."""
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError(f"{tag} isn't a version tag like v1.1.3")
    version = tag[1:]
    app_id = api.call("GET", "/apps", query={"filter[bundleId]": os.environ.get("BUNDLE_ID", "dev.ericdahl.ShowRecorder")})["data"][0]["id"]
    external = [g for g in api.call("GET", f"/apps/{app_id}/betaGroups", query={"limit": 50})["data"]
                if g["attributes"].get("isInternalGroup") is False]
    report = {}
    for platform in PLATFORMS:
        build = newest(api, app_id, version, platform)
        if not build:
            report[platform] = f"no build of {version}; skipped"
            continue
        state = build["attributes"]["processingState"]
        # The newest only: an older run of the tag is not what Eric checked.
        if state != "VALID":
            report[platform] = f"the newest build of {version} is {state}; skipped, try again once it's processed"
            continue
        if build["attributes"].get("expired"):
            report[platform] = f"the newest build of {version} has expired; skipped"
            continue
        build_id = build["id"]
        already = {g["id"] for g in api.call("GET", "/betaGroups", query={"filter[builds]": build_id, "limit": 50})["data"]}
        added = [g for g in external if g["id"] not in already]
        for group in added:
            api.call("POST", f"/betaGroups/{group['id']}/relationships/builds", body={"data": [{"type": "builds", "id": build_id}]})
        submitted = api.call("GET", f"/builds/{build_id}/betaAppReviewSubmission").get("data")
        if not submitted:
            api.call("POST", "/betaAppReviewSubmissions", body={"data": {
                "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
            review = "submitted for Beta App Review"
        else:
            review_state = (submitted.get("attributes") or {}).get("betaReviewState", "")
            review = ("Beta App Review rejected it: fix and tag again" if review_state == "REJECTED"
                      else f"already submitted for Beta App Review ({review_state.lower().replace('_', ' ') or 'state unknown'})")
        groups = ", ".join(g["attributes"]["name"] for g in added) or "no new group"
        report[platform] = f"added to {groups}; {review}"
    return report


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: testflight_promote.py vX.Y.Z")
    import ci_profile as asc
    for platform, what in promote(asc, sys.argv[1]).items():
        print(f"{platform}: {what}")


if __name__ == "__main__":
    main()
