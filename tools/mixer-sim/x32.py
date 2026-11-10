"""A simulated Behringer X32 or Midas M32 with a USB card, as the app's X32Driver talks to it over OSC on UDP 10023.
Addresses and scales from Maillot's X32 OSC protocol 4.06 and the driver (X32Driver, X32Gain, X32Routing):

- `/xinfo`: [ip, network name, model, firmware].
- `/ch/01..32/config/name`, `/color` (0-15), `/source` (0 off, 1-32 In01-32, then aux, USB, FX, buses).
- `/ch/NN/mix/on`, `/mix/fader`, `/mix/mlevel` (mono/center), its 16 sends `/mix/01..16/level`, and a pair's type
  on its odd send, `/mix/01|03|...|15/type` (0-3 before the fader, 4 POST, 5 GRP).
- `/ch/NN/gate/on`, `/thr`, `/keysrc`, `/ch/NN/dyn/on`, `/thr`, `/keysrc`.
- `/-ha/00..31/index`: the headamp (0-127) behind channel 1-32, -1 for none.
- `/headamp/000..127/gain`: 0..1 over -12..+60 dB.
- `/config/routing/CARD/1-8` .. `25-32` and `/config/routing/IN/...`: one bank number per block of 8.
- `/config/chlink/1-2` .. `31-32`, `/config/linkcfg/hadly`: stereo links, and whether they link the headamps.
"""
import behringer
from behringer import linear_float, number

CHANNELS = 32
HEADAMPS = 128
SENDS = 16
BLOCKS = ["1-8", "9-16", "17-24", "25-32"]


class X32(behringer.OSCMixer):
    PORTS = {"osc": 10023}
    HELP = ("name ch/1 TEXT, color ch/1 0-15, source ch/1 0-64, headamp ch/1 -1..127, patch card|in 1-8 BANK, "
            "gain HEADAMP(0-127) DB, set /address VALUE..., get /address")

    def __init__(self, scene, subscription_seconds=10):
        super().__init__(scene, subscription_seconds)
        self.network_name = scene.get("network_name", "X32")
        self.model = scene.get("model", "X32")
        self.firmware = scene.get("firmware", "4.06")
        p = self.params
        for n in range(1, CHANNELS + 1):
            base = "/ch/%02d" % n
            p[base + "/config/name"] = [""]
            p[base + "/config/color"] = [0]
            p[base + "/config/source"] = [n]   # channel n on In n
            p[base + "/mix/on"] = [1]
            p[base + "/mix/fader"] = [0.75]
            p[base + "/mix/mlevel"] = [0.0]
            p[base + "/gate/on"] = [0]
            p[base + "/gate/thr"] = [0.0]
            p[base + "/gate/keysrc"] = [0]
            p[base + "/dyn/on"] = [0]
            p[base + "/dyn/thr"] = [1.0]
            p[base + "/dyn/keysrc"] = [0]
            for send in range(1, SENDS + 1):
                p["%s/mix/%02d/level" % (base, send)] = [0.0]
                if send % 2 == 1:
                    p["%s/mix/%02d/type" % (base, send)] = [4]
            p["/-ha/%02d/index" % (n - 1)] = [n - 1]   # channel n on headamp n-1
        for headamp in range(HEADAMPS):
            p["/headamp/%03d/gain" % headamp] = [linear_float(0, -12, 60)]
        for index, block in enumerate(BLOCKS):
            p["/config/routing/CARD/" + block] = [index]   # the card carries AN1-8 .. AN25-32
            p["/config/routing/IN/" + block] = [index]     # the inputs are AN1-8 .. AN25-32
        for first in range(1, CHANNELS, 2):
            p["/config/chlink/%d-%d" % (first, first + 1)] = [0]
        p["/config/linkcfg/hadly"] = [0]

        for entry in scene.get("channels", []):
            n = entry["channel"]
            base = "/ch/%02d" % n
            for key, field in (("name", "config/name"), ("color", "config/color"), ("source", "config/source"),
                               ("on", "mix/on"), ("fader", "mix/fader")):
                if key in entry:
                    p["%s/%s" % (base, field)] = [entry[key]]
            if "headamp" in entry:
                p["/-ha/%02d/index" % (n - 1)] = [entry["headamp"]]
        for key, kind in (("card_blocks", "CARD"), ("input_blocks", "IN")):
            for index, value in enumerate(scene.get(key, [])):
                p["/config/routing/%s/%s" % (kind, BLOCKS[index])] = [value]
        for entry in scene.get("headamps", []):
            p["/headamp/%03d/gain" % entry["headamp"]] = [linear_float(entry["gain_db"], -12, 60)]
        for pair in scene.get("links", []):
            p["/config/chlink/%s" % pair] = [1]
        if scene.get("link_preamps"):
            p["/config/linkcfg/hadly"] = [1]
        self.apply_overrides(scene)

    @staticmethod
    def channel(target):
        group, _, n = target.partition("/")
        if group.lower() != "ch":
            raise ValueError("not a channel: %s (try ch/1)" % target)
        return number(n, 1, CHANNELS, "channel")

    def family_command(self, verb, args):
        if verb == "name" and args:
            return "ok", self.assign("/ch/%02d/config/name" % self.channel(args[0]), [" ".join(args[1:])])
        if verb == "color" and len(args) == 2:
            return "ok", self.assign("/ch/%02d/config/color" % self.channel(args[0]), [number(args[1], 0, 15, "color")])
        if verb == "source" and len(args) == 2:
            return "ok", self.assign("/ch/%02d/config/source" % self.channel(args[0]), [number(args[1], 0, 64, "source")])
        if verb == "headamp" and len(args) == 2:
            return "ok", self.assign("/-ha/%02d/index" % (self.channel(args[0]) - 1), [number(args[1], -1, 127, "headamp")])
        if verb == "patch" and len(args) == 3 and args[0].lower() in ("card", "in"):
            if args[1] not in BLOCKS:
                raise ValueError("no block %s (%s)" % (args[1], ", ".join(BLOCKS)))
            kind = "CARD" if args[0].lower() == "card" else "IN"
            return "ok", self.assign("/config/routing/%s/%s" % (kind, args[1]), [number(args[2], 0, 63, "bank")])
        if verb == "gain" and len(args) == 2:
            headamp = number(args[0], 0, HEADAMPS - 1, "headamp")
            return "ok", self.assign("/headamp/%03d/gain" % headamp, [linear_float(float(args[1]), -12, 60)])
        return None
