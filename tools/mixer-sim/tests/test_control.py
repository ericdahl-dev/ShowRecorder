"""Changing the scene while a Take runs: commands on the control port, scripted changes, and the pushes a
subscribed client gets. Run: python3 tools/mixer-sim/tests/test_control.py"""
import io
import unittest

import support
from support import Client, control


class WingControlTests(unittest.TestCase):
    def setUp(self):
        self.sim = support.start("wing", support.scene("wing-band.json"), control_port=0)
        self.client = Client()
        self.osc = self.sim.ports["osc"]

    def tearDown(self):
        self.client.close()
        self.sim.stop()

    def test_a_rename_on_the_control_port_changes_what_the_source_answers(self):
        self.assertEqual(control(self.sim, "name LCL/1 Kick In"), "ok")
        self.assertEqual(self.client.query(self.osc, "/io/in/LCL/1/name"), ("/io/in/LCL/1/name", ["Kick In"]))

    def test_a_recolor_changes_the_color_a_source_answers(self):
        self.assertEqual(control(self.sim, "color LCL/2 5"), "ok")
        self.assertEqual(self.client.query(self.osc, "/io/in/LCL/2/col")[1][2], 5)

    def test_a_repatch_changes_what_a_usb_output_carries(self):
        self.assertEqual(control(self.sim, "patch usb 3 A/2"), "ok")
        self.assertEqual(self.client.query(self.osc, "/io/out/USB/3/grp")[1], ["A"])
        self.assertEqual(self.client.query(self.osc, "/io/out/USB/3/in")[1][2], 2)

    def test_help_lists_the_commands(self):
        answer = control(self.sim, "help")
        for word in ("name", "color", "patch", "delay", "drop", "resume", "discovery-only", "status"):
            self.assertIn(word, answer)

    def test_a_command_it_does_not_know_says_so(self):
        self.assertTrue(control(self.sim, "explode now").startswith("error: "))
        self.assertTrue(control(self.sim, "color LCL/1 13").startswith("error: "))

    def test_a_subscribed_client_gets_each_change_pushed(self):
        self.client.send(self.osc, support.osc.encode("/*S"))
        control(self.sim, "name LCL/1 Kick In")
        control(self.sim, "color LCL/1 3")
        control(self.sim, "patch usb 3 A/2")
        pushed = self.client.messages(0.3)
        self.assertIn(("/io/in/LCL/1/name", ["Kick In"]), pushed)
        self.assertIn(("/io/in/LCL/1/col", [3]), pushed)
        self.assertIn(("/io/out/USB/3/grp", ["A"]), pushed)
        self.assertIn(("/io/out/USB/3/in", [2]), pushed)

    def test_only_the_last_client_to_subscribe_gets_pushes(self):
        other = Client()
        try:
            self.client.send(self.osc, support.osc.encode("/*S"))
            control(self.sim, "name ch/1 One")   # the subscription has landed once a command's answer is back
            other.send(self.osc, support.osc.encode("/*S"))
            control(self.sim, "status")
            self.client.messages(0.2)
            control(self.sim, "name ch/1 Two")
            self.assertEqual(self.client.messages(0.3), [])
            self.assertIn(("/ch/1/name", ["Two"]), other.messages(0.3))
        finally:
            other.close()

    def test_a_client_set_changes_the_value_and_reaches_the_subscriber(self):
        other = Client()
        try:
            self.client.send(self.osc, support.osc.encode("/*S"))
            control(self.sim, "status")
            other.send(self.osc, support.osc.encode("/io/in/LCL/2/name", ["Snare Top"]))
            self.assertIn(("/io/in/LCL/2/name", ["Snare Top"]), self.client.messages(0.3))
            self.assertEqual(other.query(self.osc, "/io/in/LCL/2/name")[1], ["Snare Top"])
        finally:
            other.close()

    def test_a_subscription_runs_out_unless_renewed(self):
        self.sim.stop()
        self.sim = support.start("wing", support.scene("wing-band.json"), control_port=0, subscription_seconds=0.3)
        self.osc = self.sim.ports["osc"]
        self.client.send(self.osc, support.osc.encode("/*S"))
        control(self.sim, "status")
        self.client.messages(0.5)
        control(self.sim, "name LCL/1 Late")
        self.assertEqual(self.client.messages(0.3), [])


class LogTests(unittest.TestCase):
    def test_every_message_received_and_sent_is_logged(self):
        log = io.StringIO()
        sim = support.start("wing", support.scene("wing-band.json"), log=log)
        client = Client()
        try:
            client.ask(sim.ports["knock"], b"WING?")
            client.query(sim.ports["osc"], "/io/in/LCL/1/name")
            sim.stop()
            lines = log.getvalue().splitlines()
            self.assertTrue(any("<- 127.0.0.1:" in line and "knock" in line and "WING?" in line for line in lines), lines)
            self.assertTrue(any("-> 127.0.0.1:" in line and "WING,127.0.0.1,FOH-WING" in line for line in lines), lines)
            self.assertTrue(any("<- " in line and "/io/in/LCL/1/name" in line for line in lines), lines)
            self.assertTrue(any("-> " in line and "/io/in/LCL/1/name" in line and "Kick" in line for line in lines), lines)
        finally:
            client.close()
            sim.stop()


if __name__ == "__main__":
    unittest.main()
