#!/usr/bin/env python3
"""A Mixer Link test bench: answers on the network like a Behringer mixer, so the app's Mixer Link can be tried from
a real iPhone, iPad or Mac without the mixer. Pure Python 3 standard library. See README.md.

    python3 tools/mixer-sim/mixer_sim.py --family wing --scene tools/mixer-sim/scenes/wing-band.json
"""
import argparse
import heapq
import json
import os
import selectors
import shlex
import socket
import sys
import threading
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import osc  # noqa: E402
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


def describe(data):
    """One datagram as a log shows it: an OSC message's address and arguments, or the text."""
    message = osc.decode(data)
    if message is None:
        return repr(data.decode("utf-8", "replace"))
    address, args = message
    return " ".join([address] + [repr(arg) for arg in args])


class Simulator:
    """One simulated mixer: a family's sockets and its scene, served on a background thread.

    `ports` is "real" (the mixer's own ports), "free" (any free ports, for tests) or a {role: port} dict.
    `control_port`, when not None, opens a control port on 127.0.0.1 (0: any free port) that takes one text command
    per datagram and answers with one line (see `command`).

    Fault modes, also switched live by `command`:
    - `discovery_only`: answer discovery (the WING knock, `/xinfo`) and nothing else, as wingemul does over OSC.
    - `delay_ms`: send every reply and push this late.
    - `drop_after`: seconds after start, stop answering anything, as a mixer that drops off the network.
    `script`: [{"at": seconds, "command": "..."}], control commands run that long after start.
    `log`: a text stream that gets a line for every datagram received and sent, and every command."""

    def __init__(self, family, scene, bind="0.0.0.0", ports="real", control_port=None, subscription_seconds=10,
                 discovery_only=False, delay_ms=0, drop_after=None, script=(), log=None):
        self.family = family
        self.log = log
        self.mixer = FAMILIES[family](scene, subscription_seconds=subscription_seconds)
        self.bind = bind
        self.requested_ports = ports
        self.control_port = control_port
        self.discovery_only = discovery_only
        self.delay = delay_ms / 1000.0
        self.dropped = False
        self.drop_after = drop_after
        self.script = list(script)
        self.ports = {}
        self._sockets = {}
        self._selector = selectors.DefaultSelector()
        self._lock = threading.RLock()
        self._stopping = threading.Event()
        self._thread = None
        self._timers = []   # a heap of (due, sequence, function)
        self._sequence = 0

    def _port_for(self, role, real):
        if self.requested_ports == "real":
            return real
        if self.requested_ports == "free":
            return 0
        return self.requested_ports.get(role, real)

    def _open(self, role, host, port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        sock.setblocking(False)
        self._sockets[role] = sock
        self.ports[role] = sock.getsockname()[1]
        self._selector.register(sock, selectors.EVENT_READ, role)

    def start(self):
        for role, real in self.mixer.PORTS.items():
            self._open(role, self.bind, self._port_for(role, real))
        if self.control_port is not None:
            self._open("control", "127.0.0.1", self.control_port)
        if self.drop_after is not None:
            self._after(self.drop_after, self._drop)
        for step in self.script:
            self._after(float(step["at"]), lambda line=step["command"]: self.command(line))
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

    def _log(self, text):
        if self.log is None:
            return
        now = time.time()
        stamp = time.strftime("%H:%M:%S", time.localtime(now)) + ".%03d" % int(now % 1 * 1000)
        try:
            self.log.write("%s %s\n" % (stamp, text))
            self.log.flush()
        except (OSError, ValueError):
            pass

    def _after(self, seconds, function):
        with self._lock:
            self._sequence += 1
            heapq.heappush(self._timers, (time.monotonic() + seconds, self._sequence, function))

    def _drop(self):
        self.dropped = True

    def command(self, line):
        """Carries out one control command and returns its answer: "ok", a value, or "error: ..."."""
        try:
            words = shlex.split(line)
        except ValueError as error:
            return "error: %s" % error
        if not words:
            return "error: empty command"
        try:
            with self._lock:
                answer = self._simulator_command(words[0].lower(), words[1:])
                if answer is None:
                    answer, sends = self.mixer.command(words)
                    self._send_all(sends)
        except ValueError as error:  # a family says why it can't carry out a command with a ValueError
            answer = "error: %s" % error
        self._log("command: %s => %s" % (" ".join(words), answer))
        return answer

    def _simulator_command(self, verb, args):
        """The commands every family takes, or None for one the family carries out."""
        if verb == "help":
            return "%s; status, discovery-only on|off, delay MS, drop, drop-after S, resume" % self.mixer.HELP
        if verb == "status":
            faults = [name for name, on in (("discovery-only", self.discovery_only), ("dropped", self.dropped)) if on]
            if self.delay:
                faults.append("delay %d ms" % round(self.delay * 1000))
            return "%s: %s; %s" % (self.family, ", ".join("%s %d" % item for item in self.ports.items()),
                                   ", ".join(faults) or "no faults")
        if verb == "discovery-only" and args in (["on"], ["off"]):
            self.discovery_only = args == ["on"]
            return "ok"
        if verb == "delay" and len(args) == 1:
            self.delay = max(0, float(args[0])) / 1000.0
            return "ok"
        if verb == "drop" and not args:
            self.dropped = True
            return "ok"
        if verb == "drop-after" and len(args) == 1:
            self._after(float(args[0]), self._drop)
            return "ok"
        if verb == "resume" and not args:
            self.dropped = False
            return "ok"
        return None

    def _send_all(self, sends):
        """Sends replies and pushes, `delay` late; nothing while dropped or answering discovery only."""
        if self.dropped:
            return
        if self.delay:
            sends = list(sends)
            if sends:
                self._after(self.delay, lambda: self._send_now(sends))
            return
        self._send_now(sends)

    def _send_now(self, sends):
        if self.dropped:
            return
        for role, data, peer in sends:
            sock = self._sockets.get(role)
            if sock is not None:
                self._log("-> %s:%d %s %s" % (peer[0], peer[1], role, describe(data)))
                try:
                    sock.sendto(data, peer)
                except OSError:
                    pass

    def _run_due_timers(self):
        while True:
            with self._lock:
                if not self._timers or self._timers[0][0] > time.monotonic():
                    return
                _, _, function = heapq.heappop(self._timers)
            function()

    def _wait(self):
        with self._lock:
            if not self._timers:
                return 0.05
            return min(0.05, max(0.0, self._timers[0][0] - time.monotonic()))

    def _serve(self):
        while not self._stopping.is_set():
            self._run_due_timers()
            for key, _ in self._selector.select(timeout=self._wait()):
                role = key.data
                try:
                    data, peer = key.fileobj.recvfrom(65535)
                except OSError:
                    continue
                if role == "control":
                    answer = self.command(data.decode("utf-8", "replace"))
                    try:
                        key.fileobj.sendto(answer.encode(), peer)   # the control port answers even while dropped
                    except OSError:
                        pass
                    continue
                with self._lock:
                    ignored = self.dropped or (self.discovery_only and not self.mixer.is_discovery(role, data))
                    why = "dropped" if self.dropped else "discovery only"
                    self._log("<- %s:%d %s %s%s" % (peer[0], peer[1], role, describe(data),
                                                    " (not answered: %s)" % why if ignored else ""))
                    if ignored:
                        continue
                    self._send_all(self.mixer.handle(role, data, peer, local_ip_for(peer[0])))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", required=True, choices=sorted(FAMILIES))
    parser.add_argument("--scene", required=True, help="a scene JSON file (see scenes/)")
    parser.add_argument("--bind", default="0.0.0.0", help="address to listen on (default all)")
    parser.add_argument("--port", action="append", default=[], metavar="ROLE=N",
                        help="listen for ROLE (knock, osc, ...) on port N instead of the mixer's own; 0 for any free port")
    parser.add_argument("--control-port", type=int, default=None, metavar="N",
                        help="also take commands on UDP 127.0.0.1:N (0 for any free port)")
    parser.add_argument("--discovery-only", action="store_true", help="answer discovery only, nothing on the control port")
    parser.add_argument("--delay-ms", type=float, default=0, metavar="MS", help="send every reply this late")
    parser.add_argument("--drop-after", type=float, default=None, metavar="S", help="stop answering S seconds after start")
    parser.add_argument("--script", default=None, help='a JSON list of {"at": seconds, "command": "..."}')
    parser.add_argument("--subscription-seconds", type=float, default=10, metavar="S",
                        help="how long a subscription (/xremote, /*S) lasts unless renewed (default 10, as the mixers)")
    parser.add_argument("--log", default=None, metavar="FILE", help="log every message here (default: standard error)")
    parser.add_argument("--quiet", action="store_true", help="log nothing")
    args = parser.parse_args(argv)
    ports = "real"
    if args.port:
        ports = {}
        for item in args.port:
            role, _, number = item.partition("=")
            ports[role] = int(number)
    log = None if args.quiet else (open(args.log, "a", encoding="utf-8") if args.log else sys.stderr)
    sim = Simulator(args.family, load_scene(args.scene), bind=args.bind, ports=ports, control_port=args.control_port,
                    subscription_seconds=args.subscription_seconds, discovery_only=args.discovery_only,
                    delay_ms=args.delay_ms, drop_after=args.drop_after,
                    script=load_scene(args.script) if args.script else (), log=log).start()
    print("mixer-sim: %s on %s: %s" % (args.family, args.bind,
                                       ", ".join("%s %d" % item for item in sim.ports.items())), flush=True)
    try:
        # Commands typed here change the scene live; with no terminal (stdin closed) it just keeps serving.
        for line in sys.stdin:
            if line.strip() in ("quit", "exit"):
                break
            if line.strip():
                print(sim.command(line), flush=True)
        else:
            threading.Event().wait()
    except KeyboardInterrupt:
        pass
    finally:
        sim.stop()


if __name__ == "__main__":
    main()
