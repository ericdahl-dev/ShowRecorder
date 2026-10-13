#!/usr/bin/env python3
"""Tests for the Kit coverage table (#576): llvm-cov's summary JSON in, Markdown out. No toolchain needed.
Run: python3 scripts/test_coverage.py"""
import os, sys, unittest

sys.dont_write_bytecode = True  # scripts/__pycache__ is tracked; running the tests mustn't change it

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coverage_table as table


def file(path, lines, lines_covered, functions, functions_covered):
    """One file as `llvm-cov export -summary-only` lists it."""
    return {"filename": path, "summary": {
        "lines": {"count": lines, "covered": lines_covered},
        "functions": {"count": functions, "covered": functions_covered},
    }}


def export(*files):
    return {"data": [{"files": list(files)}]}


KIT = "/repo/Packages/ShowRecorderKit/Sources"


class CoverageTableTests(unittest.TestCase):
    def test_one_file_gives_its_module_row(self):
        md = table.markdown(export(file(f"{KIT}/Recording/Recorder.swift", 200, 190, 40, 36)))
        self.assertIn("| Recording | 95.0% | 90.0% | 1 |", md)


    def test_modules_add_up_to_a_total_row(self):
        md = table.markdown(export(
            file(f"{KIT}/Recording/Recorder.swift", 100, 90, 10, 9),
            file(f"{KIT}/Recording/Show.swift", 100, 100, 10, 10),
            file(f"{KIT}/OSC/OSC.swift", 200, 150, 20, 10),
        ))
        self.assertIn("| Recording | 95.0% | 95.0% | 2 |", md)
        self.assertIn("| OSC | 75.0% | 50.0% | 1 |", md)
        self.assertIn("| **All** | **85.0%** | **72.5%** | **3** |", md)

    def test_lowest_files_come_first_and_are_capped(self):
        files = [file(f"{KIT}/Recording/File{n:02}.swift", 100, 100 - n, 10, 10) for n in range(15)]
        md = table.markdown(export(*files), lowest=3)
        lowest = md.split("### Lowest")[1]
        self.assertIn("| Recording/File14.swift | 86.0% | 100.0% |", lowest)
        self.assertLess(lowest.index("File14"), lowest.index("File13"))
        self.assertLess(lowest.index("File13"), lowest.index("File12"))
        self.assertNotIn("File11", lowest)

    def test_tests_and_build_products_are_left_out(self):
        md = table.markdown(export(
            file(f"{KIT}/OSC/OSC.swift", 100, 50, 10, 5),
            file("/repo/Packages/ShowRecorderKit/Tests/OSCTests/OSCTests.swift", 100, 100, 10, 10),
            file("/repo/Packages/ShowRecorderKit/.build/checkouts/swift-x/Sources/X/X.swift", 100, 0, 10, 0),
        ))
        self.assertIn("| **All** | **50.0%** | **50.0%** | **1** |", md)
        self.assertNotIn("OSCTests", md)
        self.assertNotIn("X.swift", md)

if __name__ == "__main__":
    unittest.main()
