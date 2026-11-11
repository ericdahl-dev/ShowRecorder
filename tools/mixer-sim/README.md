# mixer-sim: a Mixer Link test bench

`mixer_sim.py` answers on the network like a Behringer mixer, so the app's Mixer Link can be tried from a real
iPhone, iPad or Mac without the mixer on the desk. It answers the same messages the app's drivers send
(`Packages/ShowRecorderKit/Sources/MixerLink/`), from a scene file: model, firmware, Source names and colors, and USB
routing.

Pure Python 3 standard library: no pip, nothing to install. Runs on Linux and macOS.

Families:

| Family | `--family` | Ports | What it answers |
|---|---|---|---|
| Behringer WING, WING Compact, WING Rack | `wing` | UDP 2222 (knock), UDP 2223 (OSC) | `WING?`, `/?`, USB routing, Source and channel names and colors |

## Run it

```sh
python3 tools/mixer-sim/mixer_sim.py --family wing --scene tools/mixer-sim/scenes/wing-band.json
```

It prints where it listens, for example `mixer-sim: wing on 0.0.0.0: knock 2222, osc 2223`, then logs every message
it receives and sends to standard error, and runs until Ctrl-C or `quit`.

- `--bind ADDRESS`: listen on one address only (default: all of them). Use the host's LAN address, or 127.0.0.1 for
  tests on the same machine.
- `--port ROLE=N`: listen for a role (`knock`, `osc`) on another port; `0` takes any free port. The app always asks
  the real ports, so this is for tests and for a second simulator on the same host.
- `--log FILE`: write the log to a file instead; `--quiet`: no log.
- `--control-port N`: also take commands on UDP `127.0.0.1:N` (see below).
- Fault modes: `--discovery-only`, `--delay-ms MS`, `--drop-after S` (see below).
- `--script FILE`: run commands at set times (see below).
- `--subscription-seconds S`: how long a subscription lasts unless renewed (default 10, as on the mixers).

## Change the scene live

Type a command and Enter in the terminal the simulator runs in; it answers `ok`, a value or `error: ...`. Or send
one command per UDP datagram to the control port, which answers the same way, for example from another terminal:

```sh
echo 'name LCL/11 Lead Vox 2' | nc -u -w1 127.0.0.1 9999   # started with --control-port 9999
```

| Command | What it does |
|---|---|
| `name LCL/1 Kick In` | Renames a Source (WING: `LCL/1`, `A/3`, ...) or an input channel (`ch/1`) |
| `color LCL/1 5` | Changes a color (WING: 1-12) |
| `patch usb 3 LCL/9` | Repatches a USB output (WING: 1-48; a Source or a mix such as `MAIN/1`, or `OFF/1`) |
| `discovery-only on` / `off` | Answers discovery (the WING knock) and nothing else, as wingemul does over OSC |
| `delay 300` | Sends every reply and push 300 ms late (`delay 0` to stop) |
| `drop` / `resume` | Stops answering anything, as a mixer that drops off the network, and comes back |
| `drop-after 30` | Drops 30 seconds from now |
| `status`, `help` | Where it listens and which faults are on; the commands |

A client subscribed for live updates gets each change pushed, as the mixer would. WING: `/*S` (or `/*s`) on the OSC
port subscribes the sender for 10 seconds; only the last client to ask is subscribed (WING Remote Protocols, pp. 14
and 28). A change pushes the parameter's new value: text as `,s`, an integer as `,i` after `/*S` and `,sfi` after
`/*s`. An OSC set from a client (`/io/in/LCL/1/name ,s "Kick In"`) changes the scene the same way.

A script is a JSON list of commands with the seconds after start each one runs; `scripts/wing-take.json` renames,
recolors and repatches during the first minute, then drops off for 15 seconds:

```json
[{"at": 20, "command": "name LCL/11 Lead Vox 2"}, {"at": 60, "command": "drop"}, {"at": 75, "command": "resume"}]
```

The log has one line per message, `<-` received and `->` sent, with the peer, the port's role and the OSC address
and arguments (or the text), plus a line per command:

```
14:02:11.120 <- 192.168.1.23:52011 knock 'WING?'
14:02:11.120 -> 192.168.1.23:52011 knock 'WING,192.168.1.40,FOH-WING,ngc-full,S1234,3.1.1'
14:02:11.300 <- 192.168.1.23:60433 osc /io/out/USB/1/grp
14:02:11.300 -> 192.168.1.23:60433 osc /io/out/USB/1/grp 'LCL'
```

Where to run it:

- **This Linux laptop (omarchy-laptop):** Tailscale must be off, or the phone's packets don't reach it. Patrick
  Maillot's WING emulator (wingemul) may already hold UDP 2222 here: while it runs, a WING simulator can't take port
  2222 (`Address already in use`). Use another machine for the WING, or ask before stopping wingemul.
- **hermes** (`ssh hermes`): check out the repo and run the same command. hermes must be on the phone's LAN.
- **A Mac:** the same command with the system `python3`. macOS asks once whether Python may accept incoming network
  connections: allow it.

## Point the app at it

The phone, iPad or Mac running the app must reach the simulator's host on the LAN: same Wi-Fi or wired network, no
VPN in the way, and the host's firewall open for the ports above (on Linux with ufw, for example
`sudo ufw allow 2222:2223/udp`; remove the rule when done).

1. Start the simulator on the host and note the host's LAN address (`ip -4 addr` on Linux, `ipconfig getifaddr en0`
   on a Mac).
2. In the app: Settings > Mixer Link > **Find Mixers** lists it (it asks every address on the phone's network), or
   type the host's address in **Mixer IP address** and tap **Connect**.
3. The Stems' names and colors on the record screen come from the scene.

**Mixer Link shows only for a matching audio interface.** The app offers Mixer Link only while the Ready audio
interface's name says it is a mixer of a known family (an XR18, an X32 card, a WING). The built-in microphone and the
Demo signal get no Mixer Link section in Settings. So the simulator is reached from a device with a matching USB audio
interface plugged in. The WING family is offered only in Debug builds for now (`WingAvailability`).

## Scenes

A scene is a JSON file in `tools/mixer-sim/scenes/`. They are plain data, so the package's Swift tests can load the
same files as fixtures later (from the repository: `tools/mixer-sim/scenes/<name>.json`).

WING scene (`scenes/wing-band.json`):

| Key | Meaning |
|---|---|
| `family` | `"wing"` |
| `network_name`, `model`, `serial`, `firmware` | The identity the knock and `/?` answer: `WING,<ip>,<name>,<model>,<serial>,<firmware>`. `model` is `ngc-full` (full-size), `wing-compact`, `wing-rack` or `wing-bk`. The IP is the host's own address as the asker sees it. |
| `sources` | `[{"source": "LCL/1", "name": "Kick", "color": 9}]`: each Source's name (`/io/in/LCL/1/name`) and color 1-12 (`/col`). Any Source left out has an empty name and color 1. |
| `usb_outputs` | `[{"usb": 1, "source": "LCL/1"}]`: what USB output 1-48 carries (`/io/out/USB/1/grp` and `/in`). A mix is a group too: `"MAIN/1"`, `"BUS/3"`. Any output left out is `OFF`. |
| `channels` | `[{"channel": 1, "name": "Kick", "color": 9, "input": "LCL/1"}]`: input channels 1-40 (`/ch/1/name`, `/col`, `/in/conn/grp`, `/in/conn/in`). Any channel left out takes `LCL/<its number>` with no name. |

An integer answers as the WING does, `,sfi`: its text, its raw 0 to 1 value and the integer. An address the scene has
no value for gets no answer.

## Tests

```sh
python3 -B -m unittest discover -s tools/mixer-sim/tests
```

They start the simulator on 127.0.0.1 and free ports (never 2222, so they run beside wingemul) and talk to it over
real UDP. Every wait has a timeout of a second or less. `scripts/verify.sh` runs them when `tools/mixer-sim/` changes.

## What it does not prove

- **USB audio.** It sends no audio. Whether a mixer's USB interface shows up on an iPhone, iPad or Mac with all its
  channels is checked only with the real mixer.
- **Real-console quirks.** It answers what the WING Remote Protocols document (Maillot, V3.0.5-1) and the app's
  drivers say, not what a console does when they differ: timing, replies to odd queries, firmware differences. The
  WING simulator in particular is built from the document alone; no real WING has been checked against it.
- **The final check stays the real hardware:** Eric's XR18, and a real WING once one is available.
