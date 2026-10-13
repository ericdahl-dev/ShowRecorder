#!/usr/bin/env python3
"""Kit code coverage as a Markdown table (#576): reads `llvm-cov export -summary-only` JSON on stdin and prints
coverage per module and the files with the least. Report only: no floor, nothing fails."""
import glob, json, os, sys


def inputs(codecov_json):
    """The profiles and test binaries for `llvm-cov`, from what `swift test --show-codecov-path` prints (#576): every
    profile in its folder, and the binary of each test bundle in the folder above it (one or one per test target)."""
    codecov = os.path.dirname(codecov_json)
    profiles = glob.glob(os.path.join(glob.escape(codecov), "*.profraw"))
    bundles = sorted(glob.glob(os.path.join(glob.escape(os.path.dirname(codecov)), "*.xctest")))
    binaries = [os.path.join(b, "Contents", "MacOS", os.path.basename(b)[:-len(".xctest")]) for b in bundles]
    return profiles, binaries


def module(path):
    """The Kit module a source file belongs to: the folder after `Sources/`."""
    parts = path.split("/")
    return parts[parts.index("Sources") + 1] if "Sources" in parts else "?"


def percent(covered, count):
    return f"{100 * covered / count:.1f}%" if count else "-"


def short(path):
    """A file as "Module/File.swift", from the folder after `Sources/`."""
    parts = path.split("/")
    return "/".join(parts[parts.index("Sources") + 1:]) if "Sources" in parts else path


def ratio(covered, count):
    return covered / count if count else 1.0


def markdown(export, lowest=10):
    # The Kit's own sources only: not its tests, and not anything SwiftPM built into .build (dependencies' Sources).
    files = [f for unit in export["data"] for f in unit["files"]
             if "/Sources/" in f["filename"] and "/Tests/" not in f["filename"] and "/.build/" not in f["filename"]]
    modules = {}
    for f in files:
        m = modules.setdefault(module(f["filename"]), {"lines": [0, 0], "functions": [0, 0], "files": 0})
        for kind in ("lines", "functions"):
            m[kind][0] += f["summary"][kind]["covered"]
            m[kind][1] += f["summary"][kind]["count"]
        m["files"] += 1
    rows = ["| Module | Lines | Functions | Files |", "|---|---:|---:|---:|"]
    for name, m in sorted(modules.items()):
        rows.append(f"| {name} | {percent(*m['lines'])} | {percent(*m['functions'])} | {m['files']} |")
    total = {kind: [sum(m[kind][i] for m in modules.values()) for i in (0, 1)] for kind in ("lines", "functions")}
    rows.append(f"| **All** | **{percent(*total['lines'])}** | **{percent(*total['functions'])}** | **{len(files)}** |")

    def lines(f):
        return f["summary"]["lines"]["covered"], f["summary"]["lines"]["count"]

    def functions(f):
        return f["summary"]["functions"]["covered"], f["summary"]["functions"]["count"]

    worst = sorted(files, key=lambda f: (ratio(*lines(f)), short(f["filename"])))[:lowest]
    rows += ["", f"### Lowest {len(worst)} files by line coverage", "", "| File | Lines | Functions |", "|---|---:|---:|"]
    rows += [f"| {short(f['filename'])} | {percent(*lines(f))} | {percent(*functions(f))} |" for f in worst]
    return "\n".join(rows)


if __name__ == "__main__":
    # `--profiles <json>` / `--binaries <json>`: one path per line for coverage.sh (profile names have spaces).
    if len(sys.argv) == 3 and sys.argv[1] in ("--profiles", "--binaries"):
        print("\n".join(inputs(sys.argv[2])[sys.argv[1] == "--binaries"]))
    else:
        print(markdown(json.load(sys.stdin)))
