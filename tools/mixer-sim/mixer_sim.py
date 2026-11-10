#!/usr/bin/env python3
"""A Mixer Link test bench: answers on the network like a Behringer mixer, so the app's Mixer Link can be tried from
a real iPhone, iPad or Mac without the mixer. Pure Python 3 standard library. See README.md.

    python3 tools/mixer-sim/mixer_sim.py --family wing --scene tools/mixer-sim/scenes/wing-band.json
"""
import argparse
import json
import os
import selectors
import socket
import sys
import threading

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import wing  # noqa: E402

FAMILIES = {"wing": wing.Wing}


def load_scene(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def local_ip_for(peer_host):
    """This host's address as `peer_host` sees it: the one the route to it leaves from. Sends nothing."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect((peer_host, 9))
        return probe.getsockname()[0]
    except OSError:
        return "0.0.0.0"
    finally:
        probe.close()


class Simulator:
    """One simulated mixer: a family's sockets and its scene, served on a background thread.

    `ports` is "real" (the mixer's own ports), "free" (any free ports, for tests) or a {role: port} dict."""

    def __init__(self, family, scene, bind="0.0.0.0", ports="real"):
        self.mixer = FAMILIES[family](scene)
        self.bind = bind
        self.requested_ports = ports
        self.ports = {}
        self._sockets = {}
        self._selector = selectors.DefaultSelector()
        self._stopping = threading.Event()
        self._thread = None

    def _port_for(self, role, real):
        if self.requested_ports == "real":
            return real
        if self.requested_ports == "free":
            return 0
        return self.requested_ports.get(role, real)

    def start(self):
        for role, real in self.mixer.PORTS.items():
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.bind((self.bind, self._port_for(role, real)))
            sock.setblocking(False)
            self._sockets[role] = sock
            self.ports[role] = sock.getsockname()[1]
            self._selector.register(sock, selectors.EVENT_READ, role)
        self._thread = threading.Thread(target=self._serve, name="mixer-sim", daemon=True)
        self._thread.start()
        return self

    def stop(self):
        self._stopping.set()
        if self._thread:
            self._thread.join(timeout=2)
        for sock in self._sockets.values():
            self._selector.unregister(sock)
            sock.close()
        self._sockets = {}

    def _serve(self):
        while not self._stopping.is_set():
            for key, _ in self._selector.select(timeout=0.05):
                role = key.data
                try:
                    data, peer = key.fileobj.recvfrom(65535)
                except OSError:
                    continue
                for out_role, out_data, out_peer in self.mixer.handle(role, data, peer, local_ip_for(peer[0])):
                    self._sockets[out_role].sendto(out_data, out_peer)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", required=True, choices=sorted(FAMILIES))
    parser.add_argument("--scene", required=True, help="a scene JSON file (see scenes/)")
    parser.add_argument("--bind", default="0.0.0.0", help="address to listen on (default all)")
    parser.add_argument("--port", action="append", default=[], metavar="ROLE=N",
                        help="listen for ROLE (knock, osc, ...) on port N instead of the mixer's own; 0 for any free port")
    args = parser.parse_args(argv)
    ports = "real"
    if args.port:
        ports = {}
        for item in args.port:
            role, _, number = item.partition("=")
            ports[role] = int(number)
    sim = Simulator(args.family, load_scene(args.scene), bind=args.bind, ports=ports).start()
    print("mixer-sim: %s on %s: %s" % (args.family, args.bind,
                                       ", ".join("%s %d" % item for item in sim.ports.items())), flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        pass
    finally:
        sim.stop()


if __name__ == "__main__":
    main()
