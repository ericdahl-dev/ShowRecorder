#!/usr/bin/env python3
"""After the upload: set the build's "What to Test", add it to the external TestFlight group(s) and submit it
for Beta App Review, through the App Store Connect API (same key as the upload, nothing else).

Never fails the release: the upload already happened, so any problem is printed as a warning and the exit
code stays 0. Prints no secret.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, MARKETING_VERSION, BUILD_NUMBER, TAG (e.g. v0.1.12).
Notes text: docs/release-notes/<TAG>.md when it exists (written in plain words), else the titles of the pull
requests merged since the previous tag, else a fixed line.
"""
import os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ci_profile as asc  # same API helpers as the profile script

LIMIT = 4000  # Apple's limit for "What to Test"
FALLBACK = "A new ShowRecorder build. Please record a short Take and check that it saves."


def run(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True).stdout.strip()


def notes(tag: str) -> str:
    path = f"docs/release-notes/{tag}.md"
    if os.path.exists(path):
        text = open(path, encoding="utf-8").read().strip()
    else:
        previous = run("git", "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", f"{tag}^")
        titles = run("git", "log", "--first-parent", "--format=%s", f"{previous}..{tag}" if previous else tag).splitlines()
        titles = [t for t in titles if t.strip()]
        text = ("What changed:\n" + "\n".join(f"- {t}" for t in titles)) if previous and titles else FALLBACK
    return text[:LIMIT]


def find_build(app_id: str, version: str, number: str):
    """The processed build, waiting up to 40 minutes for Apple to finish."""
    for _ in range(80):
        found = asc.call("GET", "/builds", query={
            "filter[app]": app_id, "filter[version]": number, "filter[preReleaseVersion.version]": version, "limit": 5})["data"]
        if found and found[0]["attributes"]["processingState"] == "VALID":
            return found[0]
        if found and found[0]["attributes"]["processingState"] in ("FAILED", "INVALID"):
            raise RuntimeError("Apple says the build is " + found[0]["attributes"]["processingState"])
        time.sleep(30)
    raise RuntimeError("the build was not processed within 40 minutes")


def main():
    tag = os.environ["TAG"]
    text = notes(tag)
    app_id = asc.call("GET", "/apps", query={"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"][0]["id"]
    build = find_build(app_id, os.environ["MARKETING_VERSION"], os.environ["BUILD_NUMBER"])
    build_id = build["id"]
    print(f"Build {os.environ['MARKETING_VERSION']} ({os.environ['BUILD_NUMBER']}) is processed.")

    existing = asc.call("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    en = next((l for l in existing if l["attributes"]["locale"] == "en-US"), None)
    if en:
        asc.call("PATCH", f"/betaBuildLocalizations/{en['id']}", body={"data": {
            "type": "betaBuildLocalizations", "id": en["id"], "attributes": {"whatsNew": text}}})
    else:
        asc.call("POST", "/betaBuildLocalizations", body={"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print("What to Test is set.")

    groups = asc.call("GET", f"/apps/{app_id}/betaGroups", query={"limit": 50})["data"]
    for group in (g for g in groups if g["attributes"].get("isInternalGroup") is False):
        asc.call("POST", f"/betaGroups/{group['id']}/relationships/builds", body={"data": [{"type": "builds", "id": build_id}]})
        print(f"Added to the group {group['attributes']['name']}.")

    asc.call("POST", "/betaAppReviewSubmissions", body={"data": {
        "type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print("Submitted for Beta App Review.")


if __name__ == "__main__":
    try:
        main()
    except (SystemExit, Exception) as error:  # asc.call exits on an HTTP error
        print(f"::warning::TestFlight notes and distribution were not finished: {error}")
