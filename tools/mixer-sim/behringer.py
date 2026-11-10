"""What the X-Air and the X32 share: OSC on one UDP port, `/xinfo` for who it is, a query answered with the same
address and the value, a set taken silently (the XR18 echoes it), and `/xremote`, which makes the mixer push changes
to the sender for 10 seconds. The parameters are a flat {address: [arguments]} table built from the scene."""
import fnmatch
import time

import osc


class OSCMixer:
    """A family built on this fills `self.params` from the scene and names its port in PORTS."""
    PORTS = {"osc": 0}
    # The XR18 echoes each set back to its sender with no arguments (firmware 1.26, `OSCUDPClient`); the X32 doesn't.
    ECHOES_SETS = False
    HELP = ""

    def __init__(self, scene, subscription_seconds=10):
        self.network_name = scene.get("network_name", "MIXER")
        self.model = scene.get("model", "")
        self.firmware = scene.get("firmware", "")
        self.subscription_seconds = subscription_seconds
        self.subscribers = {}   # peer -> when its /xremote runs out
        self.params = {}

    def apply_overrides(self, scene):
        """`"osc": {"/address": [arguments]}` in a scene sets any parameter as is: one the scene format has no key for,
        or one the simulator doesn't know yet."""
        for address, args in scene.get("osc", {}).items():
            self.params[address] = list(args) if isinstance(args, list) else [args]
        # `"remove": ["/routing/usb/*"]` leaves parameters unanswered, as older firmware that doesn't know them.
        for pattern in scene.get("remove", []):
            for address in fnmatch.filter(list(self.params), pattern):
                del self.params[address]

    @staticmethod
    def is_discovery(role, data):
        message = osc.decode(data)
        return message is not None and message[0] == "/xinfo"

    def handle(self, role, data, peer, local_ip):
        message = osc.decode(data)
        if message is None:
            return []
        address, args = message
        if address == "/xinfo":
            return [(role, osc.encode("/xinfo", [local_ip, self.network_name, self.model, self.firmware]), peer)]
        if address == "/xremote":
            self.subscribers[peer] = time.monotonic() + self.subscription_seconds
            return []
        if args:
            if address not in self.params:
                return []
            self.params[address] = list(args)
            sends = [(role, osc.encode(address), peer)] if self.ECHOES_SETS else []
            return sends + self.push(address, skip=peer)
        if address in self.params:
            return [(role, osc.encode(address, self.params[address]), peer)]
        return []

    def push(self, address, skip=None):
        """`address`'s value to every client whose /xremote is still running (but `skip`, the one that set it)."""
        now = time.monotonic()
        self.subscribers = {peer: until for peer, until in self.subscribers.items() if until > now}
        data = osc.encode(address, self.params[address])
        return [("osc", data, peer) for peer in self.subscribers if peer != skip]

    def assign(self, address, args):
        """Sets a parameter from a control command and returns the pushes. Only addresses the mixer has."""
        if address not in self.params:
            raise ValueError("no such parameter: %s" % address)
        self.params[address] = list(args)
        return self.push(address)

    def command(self, words):
        """`set /address value ...` sets any parameter the mixer has; a family adds its own commands in `family_command`."""
        verb, args = words[0].lower(), words[1:]
        if verb == "set" and len(args) >= 2:
            return "ok", self.assign(args[0], [parse_value(text) for text in args[1:]])
        if verb == "get" and len(args) == 1:
            if args[0] not in self.params:
                raise ValueError("no such parameter: %s" % args[0])
            return " ".join(repr(value) for value in self.params[args[0]]), []
        result = self.family_command(verb, args)
        if result is None:
            raise ValueError("unknown command: %s" % " ".join(words))
        return result

    def family_command(self, verb, args):
        return None


def parse_value(text):
    """A command's value: an int, a float (with a dot) or text."""
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return text


def number(text, low, high, what):
    try:
        value = int(text)
    except ValueError:
        raise ValueError("not a number: %s" % text)
    if not low <= value <= high:
        raise ValueError("%s %d is out of range (%d-%d)" % (what, value, low, high))
    return value


def linear_float(db, low, high):
    """dB on a linear scale from `low` to `high` as the 0..1 OSC float (preamp gain, thresholds)."""
    return (max(low, min(high, float(db))) - low) / (high - low)
