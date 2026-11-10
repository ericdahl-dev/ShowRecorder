"""Fault modes: a mixer that answers discovery only, answers late, or drops off mid-session; set as options at
start and as live commands. Run: python3 tools/mixer-sim/tests/test_faults.py"""
import time
import unittest

import support
from support import Client, control


class FaultTests(unittest.TestCase):
    def setUp(self):
        self.client = Client()
        self.sim = None

    def tearDown(self):
        self.client.close()
        if self.sim:
            self.sim.stop()

    def start(self, **options):
        self.sim = support.start("wing", support.scene("wing-band.json"), control_port=0, **options)
        return self.sim

    def knock(self, timeout=support.WAIT):
        data, _ = self.client.ask(self.sim.ports["knock"], b"WING?", timeout)
        return data

    def name(self, timeout=support.WAIT):
        return self.client.query(self.sim.ports["osc"], "/io/in/LCL/1/name", timeout=timeout)

    def test_discovery_only_answers_the_knock_but_no_osc(self):
        self.start(discovery_only=True)
        self.assertIsNotNone(self.knock())
        self.assertIsNone(self.name(timeout=0.3))

    def test_discovery_only_can_be_switched_live(self):
        self.start()
        self.assertEqual(control(self.sim, "discovery-only on"), "ok")
        self.assertIsNone(self.name(timeout=0.3))
        self.assertEqual(control(self.sim, "discovery-only off"), "ok")
        self.assertIsNotNone(self.name())

    def test_slow_replies_arrive_after_the_delay(self):
        self.start(delay_ms=300)
        began = time.monotonic()
        self.assertIsNotNone(self.name())
        self.assertGreaterEqual(time.monotonic() - began, 0.28)

    def test_the_delay_can_be_changed_live(self):
        self.start()
        self.assertEqual(control(self.sim, "delay 300"), "ok")
        self.assertIsNone(self.name(timeout=0.15))
        self.assertEqual(control(self.sim, "delay 0"), "ok")
        self.client.messages(0.3)   # the late reply to the first query
        began = time.monotonic()
        self.assertIsNotNone(self.name())
        self.assertLess(time.monotonic() - began, 0.2)

    def test_it_drops_off_after_the_given_time(self):
        self.start(drop_after=0.3)
        self.assertIsNotNone(self.name())
        time.sleep(0.4)
        self.assertIsNone(self.knock(timeout=0.3))
        self.assertIsNone(self.name(timeout=0.3))

    def test_drop_and_resume_live(self):
        self.start()
        self.assertEqual(control(self.sim, "drop"), "ok")
        self.assertIsNone(self.knock(timeout=0.3))
        self.assertEqual(control(self.sim, "resume"), "ok")
        self.assertIsNotNone(self.knock())

    def test_a_dropped_mixer_pushes_nothing(self):
        self.start()
        self.client.send(self.sim.ports["osc"], support.osc.encode("/*S"))
        control(self.sim, "status")
        control(self.sim, "drop")
        control(self.sim, "name LCL/1 Gone")
        self.assertEqual(self.client.messages(0.3), [])


class ScriptTests(unittest.TestCase):
    def test_scripted_changes_happen_at_their_time(self):
        sim = support.start("wing", support.scene("wing-band.json"),
                            script=[{"at": 0.2, "command": "name LCL/1 Kick In"},
                                    {"at": 0.3, "command": "patch usb 1 LCL/9"}])
        client = Client()
        try:
            osc = sim.ports["osc"]
            self.assertEqual(client.query(osc, "/io/in/LCL/1/name")[1], ["Kick"])
            time.sleep(0.5)
            self.assertEqual(client.query(osc, "/io/in/LCL/1/name")[1], ["Kick In"])
            self.assertEqual(client.query(osc, "/io/out/USB/1/in")[1][2], 9)
        finally:
            client.close()
            sim.stop()


if __name__ == "__main__":
    unittest.main()
