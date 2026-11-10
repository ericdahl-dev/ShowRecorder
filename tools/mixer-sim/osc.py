"""A small OSC 1.0 codec: one message per datagram, int32 (i), float32 (f) and string (s) arguments, as the
Behringer mixers and the app's OSC package use them. Bundles are not read (the app refuses them too)."""
import struct


def _pad(raw):
    return raw + b"\0" * (4 - len(raw) % 4)


def _string(text):
    return _pad(text.encode("utf-8"))


def encode(address, args=()):
    """One OSC message. A Python int is sent as `i`, a float as `f`, anything else as `s`."""
    tags = ","
    body = b""
    for arg in args:
        if isinstance(arg, bool):
            arg = int(arg)
        if isinstance(arg, int):
            tags += "i"
            body += struct.pack(">i", arg)
        elif isinstance(arg, float):
            tags += "f"
            body += struct.pack(">f", arg)
        else:
            tags += "s"
            body += _string(str(arg))
    return _string(address) + _string(tags) + body


def _read_string(data, offset):
    end = data.index(b"\0", offset)
    text = data[offset:end].decode("utf-8", "replace")
    return text, offset + ((end - offset) // 4 + 1) * 4


def decode(data):
    """(address, [args]) for an OSC message, or None for anything else (plain text, a bundle, a broken packet)."""
    try:
        if not data.startswith(b"/"):
            return None
        address, offset = _read_string(data, 0)
        if offset >= len(data):
            return address, []
        tags, offset = _read_string(data, offset)
        if not tags.startswith(","):
            return None
        args = []
        for tag in tags[1:]:
            if tag == "i":
                args.append(struct.unpack(">i", data[offset:offset + 4])[0])
                offset += 4
            elif tag == "f":
                args.append(struct.unpack(">f", data[offset:offset + 4])[0])
                offset += 4
            elif tag == "s":
                value, offset = _read_string(data, offset)
                args.append(value)
            else:
                return None
        return address, args
    except (ValueError, struct.error, IndexError):
        return None
