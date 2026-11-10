"""A simulated Behringer WING (WING, WING Compact, WING Rack), from the WING Remote Protocols document (Maillot,
V3.0.5-1) and the app's WingDriver (#417). Discovery is the plain text knock `WING?` on UDP 2222; parameters are OSC
on UDP 2223.

What it answers, with the document's page numbers:
- `WING?` on 2222, and `/?` on 2223: "WING,<ip>,<name>,<model>,<serial>,<firmware>" (pp. 14, 18).
- `/io/out/USB/1..48/grp` (text) and `/in` (1..64): what each USB output carries (p. 40).
- `/io/in/<grp>/<n>/name` (text) and `/col` (1..12): each Source's name and color (pp. 35-38).
- `/ch/1..40/name`, `/col`, `/in/conn/grp` and `/in/conn/in` (p. 41).
A text or enum parameter answers ",s"; an integer answers ",sfi": its text, its raw 0..1 value and the integer
(pp. 18-19). An address it doesn't know gets no answer.
"""
import osc

USB_OUTPUTS = 48
CHANNELS = 40
# Source groups that carry a named, colored signal, and the mix groups a USB output can also take (p. 40).
SOURCE_GROUPS = {"LCL", "AUX", "A", "B", "C", "SC", "USB", "CRD", "MOD", "PLAY", "AES", "USR", "OSC"}
OUTPUT_GROUPS = SOURCE_GROUPS | {"OFF", "BUS", "MAIN", "MTX", "SEND", "MON"}
# The most inputs a group has: `/io/out/USB/n/in` takes 1..64 (p. 40).
GROUP_SIZE = 64
COLORS = (1, 12)


def parse_source(text):
    """"LCL/1" as ("LCL", 1)."""
    group, number = text.split("/")
    return group.upper(), int(number)


class Wing:
    PORTS = {"knock": 2222, "osc": 2223}

    def __init__(self, scene):
        self.network_name = scene.get("network_name", "WING")
        self.model = scene.get("model", "ngc-full")
        self.serial = scene.get("serial", "0")
        self.firmware = scene.get("firmware", "3.1.1")
        self.sources = {}
        for entry in scene.get("sources", []):
            self.sources[parse_source(entry["source"])] = {"name": entry.get("name", ""), "color": entry.get("color", 1)}
        self.usb = {n: ("OFF", 1) for n in range(1, USB_OUTPUTS + 1)}
        for entry in scene.get("usb_outputs", []):
            self.usb[entry["usb"]] = parse_source(entry["source"])
        # A channel the scene leaves out takes the local input of its number, with no name.
        self.channels = {n: {"name": "", "color": 1, "input": ("LCL", n)} for n in range(1, CHANNELS + 1)}
        for entry in scene.get("channels", []):
            channel = self.channels[entry["channel"]]
            channel["name"] = entry.get("name", "")
            channel["color"] = entry.get("color", 1)
            if "input" in entry:
                channel["input"] = parse_source(entry["input"])

    def identity(self, ip):
        return "WING,%s,%s,%s,%s,%s" % (ip, self.network_name, self.model, self.serial, self.firmware)

    def source(self, group, number):
        return self.sources.get((group, number), {"name": "", "color": 1})

    def handle(self, role, data, peer, local_ip):
        """What to send for one datagram received on `role`'s port: a list of (role, bytes, address)."""
        if role == "knock":
            return [("knock", self.identity(local_ip).encode(), peer)] if data == b"WING?" else []
        message = osc.decode(data)
        if message is None:
            return []
        address, args = message
        if address == "/?":
            return [("osc", osc.encode("/?", [self.identity(local_ip)]), peer)]
        reply = self.value(address)
        return [] if reply is None else [("osc", osc.encode(address, reply), peer)]

    def value(self, address):
        """The reply arguments for a query of `address`, or None when the WING has no such parameter."""
        parts = address.strip("/").split("/")
        if len(parts) == 5 and parts[:3] == ["io", "out", "USB"] and parts[3].isdigit():
            number = int(parts[3])
            if number not in self.usb:
                return None
            group, input_number = self.usb[number]
            if parts[4] == "grp":
                return [group]
            if parts[4] == "in":
                return integer(input_number, 1, GROUP_SIZE)
            return None
        if len(parts) == 5 and parts[:2] == ["io", "in"] and parts[2] in SOURCE_GROUPS and parts[3].isdigit():
            number = int(parts[3])
            if not 1 <= number <= GROUP_SIZE:
                return None
            source = self.source(parts[2], number)
            if parts[4] == "name":
                return [source["name"]]
            if parts[4] == "col":
                return integer(source["color"], *COLORS)
            return None
        if len(parts) >= 3 and parts[0] == "ch" and parts[1].isdigit():
            channel = self.channels.get(int(parts[1]))
            if channel is None:
                return None
            field = "/".join(parts[2:])
            if field == "name":
                return [channel["name"]]
            if field == "col":
                return integer(channel["color"], *COLORS)
            if field == "in/conn/grp":
                return [channel["input"][0]]
            if field == "in/conn/in":
                return integer(channel["input"][1], 1, GROUP_SIZE)
        return None


def integer(value, low, high):
    """How the WING answers an integer: ",sfi", its text, its raw 0..1 value and the integer (pp. 18-19)."""
    raw = (value - low) / (high - low) if high > low else 0.0
    return [str(value), float(raw), int(value)]
