"""The simulated WING, as the app's WingDriver talks to it (#417): the `WING?` knock and OSC queries.
Run: python3 tools/mixer-sim/tests/test_wing.py"""
import unittest

import support
from support import Client


class WingKnockTests(unittest.TestCase):
    def setUp(self):
        self.sim = support.start("wing", support.scene("wing-band.json"))
        self.client = Client()

    def tearDown(self):
        self.client.close()
        self.sim.stop()

    def test_the_knock_gets_the_identity_text_from_the_knock_port(self):
        data, port = self.client.ask(self.sim.ports["knock"], b"WING?")
        self.assertEqual(data, b"WING,127.0.0.1,FOH-WING,ngc-full,S1234,3.1.1")
        self.assertEqual(port, self.sim.ports["knock"])

    def test_anything_else_on_the_knock_port_gets_no_reply(self):
        data, _ = self.client.ask(self.sim.ports["knock"], b"HELLO", timeout=0.3)
        self.assertIsNone(data)


class WingOSCTests(unittest.TestCase):
    def setUp(self):
        self.sim = support.start("wing", support.scene("wing-band.json"))
        self.client = Client()
        self.osc = self.sim.ports["osc"]

    def tearDown(self):
        self.client.close()
        self.sim.stop()

    def test_osc_identify_answers_the_identity_text(self):
        self.assertEqual(self.client.query(self.osc, "/?"), ("/?", ["WING,127.0.0.1,FOH-WING,ngc-full,S1234,3.1.1"]))

    def test_a_usb_output_answers_its_group_as_text_and_its_input_as_text_raw_and_int(self):
        self.assertEqual(self.client.query(self.osc, "/io/out/USB/1/grp"), ("/io/out/USB/1/grp", ["LCL"]))
        address, args = self.client.query(self.osc, "/io/out/USB/1/in")
        self.assertEqual(address, "/io/out/USB/1/in")
        self.assertEqual((args[0], args[2]), ("1", 1))
        self.assertAlmostEqual(args[1], 0.0)

    def test_a_usb_output_the_scene_leaves_out_is_off(self):
        self.assertEqual(self.client.query(self.osc, "/io/out/USB/48/grp"), ("/io/out/USB/48/grp", ["OFF"]))

    def test_the_source_on_a_usb_output_answers_its_name_and_color(self):
        self.assertEqual(self.client.query(self.osc, "/io/in/LCL/1/name"), ("/io/in/LCL/1/name", ["Kick"]))
        address, args = self.client.query(self.osc, "/io/in/LCL/1/col")
        self.assertEqual((args[0], args[2]), ("9", 9))

    def test_a_usb_output_on_a_mix_names_the_mix_group(self):
        self.assertEqual(self.client.query(self.osc, "/io/out/USB/47/grp"), ("/io/out/USB/47/grp", ["MAIN"]))

    def test_a_source_the_scene_leaves_out_has_an_empty_name(self):
        self.assertEqual(self.client.query(self.osc, "/io/in/LCL/40/name"), ("/io/in/LCL/40/name", [""]))

    def test_an_input_channel_answers_its_name_color_and_input(self):
        self.assertEqual(self.client.query(self.osc, "/ch/1/name"), ("/ch/1/name", ["Kick"]))
        self.assertEqual(self.client.query(self.osc, "/ch/1/col")[1][2], 9)
        self.assertEqual(self.client.query(self.osc, "/ch/1/in/conn/grp"), ("/ch/1/in/conn/grp", ["LCL"]))
        self.assertEqual(self.client.query(self.osc, "/ch/1/in/conn/in")[1][2], 1)

    def test_an_address_the_wing_has_no_answer_for_gets_none(self):
        self.assertIsNone(self.client.query(self.osc, "/no/such/thing", timeout=0.3))


if __name__ == "__main__":
    unittest.main()
