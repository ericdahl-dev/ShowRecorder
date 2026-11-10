"""A simulated Behringer X-Air (XR18, MR18; XR12 and XR16 by model), as the app's XAirDriver talks to it over OSC
on UDP 10024. Addresses and scales are those the driver uses, read on Eric's XR18 (firmware 1.26):

- `/xinfo`: [ip, network name, model, firmware].
- `/ch/01..16/config/name`, `/color` (0-15), `/insrc` (0-15 In01-16, 16-17 the aux line in).
- `/ch/NN/mix/on` (1 on), `/mix/fader` (0..1), `/preamp/rtnsw` (1: the channel takes USB).
- Mix Hold: `/ch/NN/gate/on`, `/gate/thr`, `/gate/keysrc`, `/dyn/on`, `/dyn/thr`, `/dyn/keysrc`, and its ten sends
  `/ch/NN/mix/01..10/level` and `/tap` (0 IN, 1 PREEQ, 2 POSTEQ, 3 PRE, 4 POST, 5 GRP).
- `/rtn/aux/config/name`, `/color`, `/mix/on`, `/mix/fader`: the aux return.
- `/routing/usb/01..18`: [source, tap]; source 0-15 Ch01-16, 16-17 AuxL/R, 18-25 FX, 26-31 Bus 1-6, 32-35 Send
  1-4, 36-37 main L/R.
- `/headamp/01..18/gain`: 0..1 over -12..+60 dB (01-16) and -12..+20 dB (17-18, the aux line in).
- `/config/chlink/1-2` .. `15-16` and `/config/linkcfg/preamp`: stereo links and whether they link the preamps.
"""
import behringer
from behringer import linear_float, number

CHANNELS = 16
USB_CHANNELS = 18
HEADAMPS = 18
SENDS = 10


def headamp_float(headamp, db):
    return linear_float(db, -12, 20) if headamp >= 17 else linear_float(db, -12, 60)


class XAir(behringer.OSCMixer):
    PORTS = {"osc": 10024}
    ECHOES_SETS = True
    HELP = ("name ch/1|aux TEXT, color ch/1|aux 0-15, input ch/1 0-17, patch usb 1-18 SOURCE(0-37), "
            "gain HEADAMP(1-18) DB, set /address VALUE..., get /address")

    def __init__(self, scene, subscription_seconds=10):
        super().__init__(scene, subscription_seconds)
        self.network_name = scene.get("network_name", "XR18")
        self.model = scene.get("model", "XR18")
        self.firmware = scene.get("firmware", "1.26")
        p = self.params
        for n in range(1, CHANNELS + 1):
            base = "/ch/%02d" % n
            p[base + "/config/name"] = [""]
            p[base + "/config/color"] = [0]
            p[base + "/config/insrc"] = [n - 1]   # channel n on In n
            p[base + "/mix/on"] = [1]
            p[base + "/mix/fader"] = [0.75]
            p[base + "/preamp/rtnsw"] = [0]
            p[base + "/gate/on"] = [0]
            p[base + "/gate/thr"] = [0.0]
            p[base + "/gate/keysrc"] = [0]
            p[base + "/dyn/on"] = [0]
            p[base + "/dyn/thr"] = [1.0]
            p[base + "/dyn/keysrc"] = [0]
            for send in range(1, SENDS + 1):
                p["%s/mix/%02d/level" % (base, send)] = [0.0]
                p["%s/mix/%02d/tap" % (base, send)] = [4]
        for field, value in (("config/name", ""), ("config/color", 0), ("mix/on", 1), ("mix/fader", 0.75)):
            p["/rtn/aux/" + field] = [value]
        for usb in range(1, USB_CHANNELS + 1):
            # USB 1-16 carry channels 1-16, 17-18 the aux return (the XR18's default).
            p["/routing/usb/%02d" % usb] = [usb - 1, 0]
        for headamp in range(1, HEADAMPS + 1):
            p["/headamp/%02d/gain" % headamp] = [headamp_float(headamp, 0)]
        for first in range(1, CHANNELS, 2):
            p["/config/chlink/%d-%d" % (first, first + 1)] = [0]
        p["/config/linkcfg/preamp"] = [0]

        for entry in scene.get("channels", []):
            base = "/ch/%02d" % entry["channel"]
            for key, field in (("name", "config/name"), ("color", "config/color"), ("insrc", "config/insrc"),
                               ("on", "mix/on"), ("fader", "mix/fader"), ("usb_return", "preamp/rtnsw")):
                if key in entry:
                    p["%s/%s" % (base, field)] = [entry[key]]
        aux = scene.get("aux_return", {})
        for key, field in (("name", "config/name"), ("color", "config/color"), ("on", "mix/on"), ("fader", "mix/fader")):
            if key in aux:
                p["/rtn/aux/" + field] = [aux[key]]
        for entry in scene.get("usb_routing", []):
            p["/routing/usb/%02d" % entry["usb"]] = [entry["source"], entry.get("tap", 0)]
        for entry in scene.get("headamps", []):
            p["/headamp/%02d/gain" % entry["headamp"]] = [headamp_float(entry["headamp"], entry["gain_db"])]
        for pair in scene.get("links", []):
            p["/config/chlink/%s" % pair] = [1]
        if scene.get("link_preamps"):
            p["/config/linkcfg/preamp"] = [1]
        self.apply_overrides(scene)

    @staticmethod
    def base(target):
        """"ch/1" as "/ch/01", "aux" as "/rtn/aux"."""
        if target.lower() == "aux":
            return "/rtn/aux"
        group, _, n = target.partition("/")
        if group.lower() != "ch":
            raise ValueError("not a channel: %s (try ch/1 or aux)" % target)
        return "/ch/%02d" % number(n, 1, CHANNELS, "channel")

    def family_command(self, verb, args):
        if verb == "name" and args:
            return "ok", self.assign(self.base(args[0]) + "/config/name", [" ".join(args[1:])])
        if verb == "color" and len(args) == 2:
            return "ok", self.assign(self.base(args[0]) + "/config/color", [number(args[1], 0, 15, "color")])
        if verb == "input" and len(args) == 2:
            return "ok", self.assign(self.base(args[0]) + "/config/insrc", [number(args[1], 0, 17, "input source")])
        if verb == "patch" and len(args) == 3 and args[0].lower() == "usb":
            usb = number(args[1], 1, USB_CHANNELS, "USB Channel")
            address = "/routing/usb/%02d" % usb
            return "ok", self.assign(address, [number(args[2], 0, 37, "source"), self.params[address][1]])
        if verb == "gain" and len(args) == 2:
            headamp = number(args[0], 1, HEADAMPS, "headamp")
            return "ok", self.assign("/headamp/%02d/gain" % headamp, [headamp_float(headamp, float(args[1]))])
        return None
