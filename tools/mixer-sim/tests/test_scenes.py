"""The scenes and scripts in the repository: each scene starts and answers discovery, and every command in each
script is one its family takes. Run: python3 tools/mixer-sim/tests/test_scenes.py"""
import glob
import json
import os
import unittest

import support
from support import Client


class ShippedFilesTests(unittest.TestCase):
    def test_every_scene_starts_and_answers_discovery(self):
        paths = sorted(glob.glob(os.path.join(support.SCENES, "*.json")))
        self.assertTrue(paths)
        for path in paths:
            scene = support.mixer_sim.load_scene(path)
            with self.subTest(scene=os.path.basename(path)):
                sim = support.start(scene["family"], scene)
                client = Client()
                try:
                    if scene["family"] == "wing":
                        self.assertIsNotNone(client.ask(sim.ports["knock"], b"WING?")[0])
                    else:
                        self.assertIsNotNone(client.query(sim.ports["osc"], "/xinfo"))
                finally:
                    client.close()
                    sim.stop()

    def test_every_scripted_command_is_one_its_family_takes(self):
        paths = sorted(glob.glob(os.path.join(support.SIM_DIR, "scripts", "*.json")))
        self.assertTrue(paths)
        for path in paths:
            family = os.path.basename(path).split("-")[0]
            scene = {"xr18": "xr18-band.json", "wing": "wing-band.json", "x32": "x32-band.json"}[family]
            with open(path, encoding="utf-8") as f:
                steps = json.load(f)
            sim = support.start(support.scene(scene)["family"], support.scene(scene))
            try:
                for step in steps:
                    with self.subTest(script=os.path.basename(path), command=step["command"]):
                        self.assertIsInstance(step["at"], (int, float))
                        self.assertEqual(sim.command(step["command"]), "ok")
            finally:
                sim.stop()


if __name__ == "__main__":
    unittest.main()
