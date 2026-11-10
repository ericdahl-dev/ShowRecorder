"""The simulator as a person runs it: `mixer_sim.py --family ... --scene ...` in its own process.
Run: python3 tools/mixer-sim/tests/test_cli.py"""
import os
import re
import select
import subprocess
import sys
import unittest

import support
from support import Client

SCRIPT = os.path.join(support.SIM_DIR, "mixer_sim.py")


class Running:
    """The simulator in a child process, stopped when the test ends, and the ports it says it listens on."""

    def __init__(self, *args):
        self.process = subprocess.Popen([sys.executable, "-B", SCRIPT, *args], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.ports = {}
        line = self.line(timeout=5)
        for role, port in re.findall(r"(\w+) (\d+)", line.split(":", 2)[-1]):
            self.ports[role] = int(port)

    def line(self, timeout):
        ready, _, _ = select.select([self.process.stdout], [], [], timeout)
        if not ready:
            raise AssertionError("mixer_sim.py printed nothing in %s s" % timeout)
        return self.process.stdout.readline()

    def stop(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


class CommandLineTests(unittest.TestCase):
    def test_it_says_where_it_listens_and_answers_there(self):
        sim = Running("--family", "wing", "--scene", os.path.join(support.SCENES, "wing-band.json"),
                      "--bind", "127.0.0.1", "--port", "knock=0", "--port", "osc=0")
        client = Client()
        try:
            self.assertEqual(set(sim.ports), {"knock", "osc"})
            self.assertNotEqual(sim.ports["knock"], 2222)
            data, _ = client.ask(sim.ports["knock"], b"WING?")
            self.assertTrue(data.startswith(b"WING,127.0.0.1,FOH-WING,"))
        finally:
            client.close()
            sim.stop()


if __name__ == "__main__":
    unittest.main()
