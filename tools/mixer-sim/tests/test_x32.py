"""The simulated X32 (X32, M32 with a USB card), as the app's X32Driver talks to it: OSC on UDP 10023.
Run: python3 tools/mixer-sim/tests/test_x32.py"""
import unittest

import support
from support import Client, control


class X32Tests(unittest.TestCase):
    def setUp(self):
        self.sim = support.start("x32", support.scene("x32-band.json"), control_port=0)
        self.client = Client()
        self.port = self.sim.ports["osc"]

    def tearDown(self):
        self.client.close()
        self.sim.stop()

    def ask(self, address, timeout=support.WAIT):
        reply = self.client.query(self.port, address, timeout=timeout)
        return None if reply is None else reply[1]

    def test_xinfo_answers_ip_name_model_and_firmware(self):
        self.assertEqual(self.ask("/xinfo"), ["127.0.0.1", "FOH-X32", "X32", "4.06"])

    def test_a_channel_answers_its_name_color_and_source(self):
        self.assertEqual(self.ask("/ch/11/config/name"), ["Lead Vox"])
        self.assertEqual(self.ask("/ch/11/config/color"), [4])
        self.assertEqual(self.ask("/ch/11/config/source"), [11])
        self.assertEqual(self.ask("/ch/17/config/source"), [11])
        self.assertEqual(self.ask("/ch/32/config/name"), [""])
        self.assertEqual(self.ask("/ch/32/config/source"), [32])

    def test_card_and_input_routing_answer_one_number_per_block(self):
        for block, value in (("1-8", 0), ("9-16", 1), ("17-24", 2), ("25-32", 3)):
            self.assertEqual(self.ask("/config/routing/CARD/" + block), [value])
            self.assertEqual(self.ask("/config/routing/IN/" + block), [value])

    def test_each_channel_answers_its_headamp_and_each_headamp_its_gain(self):
        self.assertEqual(self.ask("/-ha/00/index"), [0])
        self.assertEqual(self.ask("/-ha/16/index"), [10])
        self.assertAlmostEqual(self.ask("/headamp/010/gain")[0], (38.5 + 12) / 72, places=5)
        self.assertAlmostEqual(self.ask("/headamp/127/gain")[0], 12 / 72, places=5)

    def test_every_setting_mix_hold_reads_is_answered(self):
        for address in ("/ch/03/gate/on", "/ch/03/gate/thr", "/ch/03/gate/keysrc", "/ch/03/dyn/on", "/ch/03/dyn/thr",
                        "/ch/03/dyn/keysrc", "/ch/03/mix/fader", "/ch/03/mix/mlevel", "/ch/03/mix/on",
                        "/ch/03/mix/01/level", "/ch/03/mix/16/level", "/ch/03/mix/01/type", "/ch/03/mix/15/type",
                        "/config/chlink/31-32", "/config/linkcfg/hadly"):
            self.assertIsNotNone(self.ask(address), address)
        self.assertIsNone(self.ask("/ch/03/mix/02/type", timeout=0.3))   # a pair's type is on its odd send
        self.assertEqual(self.ask("/config/chlink/9-10"), [1])
        self.assertEqual(self.ask("/config/linkcfg/hadly"), [1])

    def test_a_set_is_taken_without_an_echo(self):
        self.client.send(self.port, support.osc.encode("/headamp/000/gain", [0.5]))
        self.assertEqual(self.client.messages(0.3), [])
        self.assertAlmostEqual(self.ask("/headamp/000/gain")[0], 0.5, places=5)

    def test_xremote_subscribers_get_changes_pushed(self):
        self.client.send(self.port, support.osc.encode("/xremote"))
        self.ask("/xinfo")
        for line in ("name ch/1 Kick In", "color ch/1 2", "source ch/2 20", "patch card 9-16 2", "patch in 1-8 1",
                     "gain 0 35", "headamp ch/2 40"):
            self.assertEqual(control(self.sim, line), "ok", line)
        pushed = self.client.messages(0.3)
        self.assertIn(("/ch/01/config/name", ["Kick In"]), pushed)
        self.assertIn(("/ch/01/config/color", [2]), pushed)
        self.assertIn(("/ch/02/config/source", [20]), pushed)
        self.assertIn(("/config/routing/CARD/9-16", [2]), pushed)
        self.assertIn(("/config/routing/IN/1-8", [1]), pushed)
        self.assertIn(("/-ha/01/index", [40]), pushed)
        self.assertTrue(any(address == "/headamp/000/gain" for address, _ in pushed))

    def test_commands_check_their_ranges(self):
        self.assertTrue(control(self.sim, "name ch/33 X").startswith("error: "))
        self.assertTrue(control(self.sim, "patch card 1-9 0").startswith("error: "))
        self.assertTrue(control(self.sim, "gain 128 0").startswith("error: "))


if __name__ == "__main__":
    unittest.main()
