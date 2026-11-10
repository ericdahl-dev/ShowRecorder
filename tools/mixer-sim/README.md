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

It prints where it listens, for example `mixer-sim: wing on 0.0.0.0: knock 2222, osc 2223`, and runs until Ctrl-C.

- `--bind ADDRESS`: listen on one address only (default: all of them). Use the host's LAN address, or 127.0.0.1 for
  tests on the same machine.
- `--port ROLE=N`: listen for a role (`knock`, `osc`) on another port; `0` takes any free port. The app always asks
  the real ports, so this is for tests and for a second simulator on the same host.

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
