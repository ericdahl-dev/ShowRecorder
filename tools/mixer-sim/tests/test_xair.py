"""The simulated X-Air (XR18, MR18), as the app's XAirDriver talks to it: OSC on one UDP port (10024 on a real one).
Run: python3 tools/mixer-sim/tests/test_xair.py"""
import unittest

import support
from support import Client, control


class XAirTests(unittest.TestCase):
    def setUp(self):
        self.sim = support.start("xair", support.scene("xr18-band.json"), control_port=0)
        self.client = Client()
        self.port = self.sim.ports["osc"]

    def tearDown(self):
        self.client.close()
        self.sim.stop()

    def ask(self, address, timeout=support.WAIT):
        reply = self.client.query(self.port, address, timeout=timeout)
        return None if reply is None else reply[1]

    def test_xinfo_answers_ip_name_model_and_firmware(self):
        self.assertEqual(self.ask("/xinfo"), ["127.0.0.1", "FOH-XR18", "XR18", "1.26"])

    def test_a_channel_answers_its_name_color_and_input_source(self):
        self.assertEqual(self.ask("/ch/11/config/name"), ["Lead Vox"])
        self.assertEqual(self.ask("/ch/11/config/color"), [4])
        self.assertEqual(self.ask("/ch/11/config/insrc"), [10])
        self.assertEqual(self.ask("/ch/16/config/name"), [""])

    def test_usb_routing_defaults_to_channels_then_the_aux_return(self):
        self.assertEqual(self.ask("/routing/usb/01")[0], 0)
        self.assertEqual(self.ask("/routing/usb/16")[0], 15)
        self.assertEqual(self.ask("/routing/usb/17")[0], 16)
        self.assertEqual(self.ask("/aux/does/not/exist", timeout=0.3), None)
        self.assertEqual(self.ask("/rtn/aux/config/name"), ["Playback"])
        self.assertEqual(self.ask("/rtn/aux/config/color"), [5])

    def test_mix_state_answers_as_the_driver_reads_it(self):
        self.assertEqual(self.ask("/ch/01/mix/on"), [1])
        self.assertAlmostEqual(self.ask("/ch/01/mix/fader")[0], 0.75, places=5)
        self.assertEqual(self.ask("/ch/01/preamp/rtnsw"), [0])

    def test_preamp_gain_is_a_float_over_its_range(self):
        self.assertAlmostEqual(self.ask("/headamp/01/gain")[0], (32 + 12) / 72, places=5)
        self.assertAlmostEqual(self.ask("/headamp/17/gain")[0], 12 / 32, places=5)

    def test_every_setting_mix_hold_reads_is_answered(self):
        for address in ("/ch/03/gate/on", "/ch/03/gate/thr", "/ch/03/gate/keysrc", "/ch/03/dyn/on", "/ch/03/dyn/thr",
                        "/ch/03/dyn/keysrc", "/ch/03/mix/01/level", "/ch/03/mix/10/tap", "/config/chlink/1-2",
                        "/config/linkcfg/preamp"):
            self.assertIsNotNone(self.ask(address), address)
        self.assertEqual(self.ask("/config/chlink/5-6"), [1])
        self.assertEqual(self.ask("/config/linkcfg/preamp"), [1])

    def test_a_set_is_echoed_with_no_arguments_and_then_answered(self):
        self.client.send(self.port, support.osc.encode("/headamp/02/gain", [0.5]))
        data, _ = self.client.receive()
        self.assertEqual(support.osc.decode(data), ("/headamp/02/gain", []))
        self.assertAlmostEqual(self.ask("/headamp/02/gain")[0], 0.5, places=5)

    def test_xremote_subscribers_get_changes_pushed_until_it_runs_out(self):
        self.client.send(self.port, support.osc.encode("/xremote"))
        self.ask("/xinfo")
        control(self.sim, "name ch/1 Kick In")
        control(self.sim, "color aux 2")
        control(self.sim, "patch usb 18 26")
        control(self.sim, "gain 1 35")
        control(self.sim, "input ch/2 5")
        pushed = self.client.messages(0.3)
        self.assertIn(("/ch/01/config/name", ["Kick In"]), pushed)
        self.assertIn(("/rtn/aux/config/color", [2]), pushed)
        self.assertIn(("/routing/usb/18", [26, 0]), pushed)
        self.assertIn(("/ch/02/config/insrc", [5]), pushed)
        self.assertTrue(any(address == "/headamp/01/gain" for address, _ in pushed))

    def test_another_clients_set_is_pushed_to_subscribers(self):
        other = Client()
        try:
            self.client.send(self.port, support.osc.encode("/xremote"))
            self.ask("/xinfo")
            other.send(self.port, support.osc.encode("/ch/04/config/name", ["Floor Tom"]))
            self.assertIn(("/ch/04/config/name", ["Floor Tom"]), self.client.messages(0.3))
        finally:
            other.close()

    def test_set_and_get_reach_any_parameter(self):
        self.assertEqual(control(self.sim, "set /ch/03/gate/on 1"), "ok")
        self.assertEqual(self.ask("/ch/03/gate/on"), [1])
        self.assertEqual(control(self.sim, "get /ch/03/gate/on"), "1")
        self.assertTrue(control(self.sim, "set /no/such 1").startswith("error: "))

    def test_discovery_only_answers_xinfo_and_nothing_else(self):
        control(self.sim, "discovery-only on")
        self.assertIsNotNone(self.ask("/xinfo"))
        self.assertIsNone(self.ask("/ch/01/config/name", timeout=0.3))


class XAirSceneTests(unittest.TestCase):
    def test_raw_osc_values_in_a_scene_override_anything(self):
        scene = {"family": "xair", "osc": {"/ch/01/gate/on": [1], "/-stat/solosw/01": [0]}}
        sim = support.start("xair", scene)
        client = Client()
        try:
            self.assertEqual(client.query(sim.ports["osc"], "/ch/01/gate/on")[1], [1])
            self.assertEqual(client.query(sim.ports["osc"], "/-stat/solosw/01")[1], [0])
        finally:
            client.close()
            sim.stop()

    def test_older_firmware_without_usb_routing_can_be_simulated(self):
        scene = {"family": "xair", "remove": ["/routing/usb/*"]}
        sim = support.start("xair", scene)
        client = Client()
        try:
            self.assertIsNone(client.query(sim.ports["osc"], "/routing/usb/01", timeout=0.3))
            self.assertEqual(client.query(sim.ports["osc"], "/ch/01/config/name")[1], [""])
        finally:
            client.close()
            sim.stop()


if __name__ == "__main__":
    unittest.main()
