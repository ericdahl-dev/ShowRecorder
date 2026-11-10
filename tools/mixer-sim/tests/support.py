"""Helpers for the mixer-sim tests: start a simulator on free localhost ports and talk to it over real UDP.

Every wait has a timeout, so a test fails instead of hanging when the simulator doesn't answer."""
import os
import socket
import sys
import time

sys.dont_write_bytecode = True  # running the tests mustn't leave __pycache__ folders behind

HERE = os.path.dirname(os.path.abspath(__file__))
SIM_DIR = os.path.dirname(HERE)
SCENES = os.path.join(SIM_DIR, "scenes")
sys.path.insert(0, SIM_DIR)

import mixer_sim  # noqa: E402
import osc  # noqa: E402

# How long a test waits for any one reply. The simulator answers in well under a millisecond on localhost.
WAIT = 1.0


def scene(name):
    return mixer_sim.load_scene(os.path.join(SCENES, name))


def start(family, scene_data, **options):
    """A running simulator on 127.0.0.1 and free ports (never the real ones: a WING emulator may own 2222)."""
    sim = mixer_sim.Simulator(family, scene_data, bind="127.0.0.1", ports="free", **options)
    sim.start()
    return sim


class Client:
    """One UDP socket, as the app has one connection per port: replies come back to the port it sent from."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(WAIT)

    def close(self):
        self.sock.close()

    def send(self, port, data):
        self.sock.sendto(data, ("127.0.0.1", port))

    def receive(self, timeout=WAIT):
        """The next datagram and the port it came from, or (None, None) after `timeout`."""
        self.sock.settimeout(timeout)
        try:
            data, (_, port) = self.sock.recvfrom(65535)
            return data, port
        except socket.timeout:
            return None, None

    def ask(self, port, data, timeout=WAIT):
        self.send(port, data)
        return self.receive(timeout)

    def query(self, port, address, *args, timeout=WAIT):
        """Sends an OSC message and returns the first reply message with the same address, or None."""
        self.send(port, osc.encode(address, list(args)))
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            data, _ = self.receive(left)
            if data is None:
                return None
            message = osc.decode(data)
            if message and message[0] == address and message[1]:
                return message

    def messages(self, timeout):
        """Every OSC message that arrives within `timeout`."""
        found = []
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return found
            data, _ = self.receive(left)
            if data is None:
                return found
            message = osc.decode(data)
            if message:
                found.append(message)
