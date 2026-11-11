# mixer-sim: a Mixer Link test bench

`mixer_sim.py` answers on the network like a Behringer mixer, so the app's Mixer Link can be tried from a real
iPhone, iPad or Mac without the mixer on the desk. It answers the same messages the app's drivers send
(`Packages/ShowRecorderKit/Sources/MixerLink/`), from a scene file: model, firmware, Source names and colors, USB
routing, preamp gains and the settings Mix Hold reads. A scene can be changed live while a Take runs, and the mixer
can be made to misbehave (answer late, drop off, answer discovery only).

Pure Python 3 standard library: no pip, nothing to install. Runs on Linux and macOS.

| Family | `--family` | Ports | What it answers |
|---|---|---|---|
| Behringer WING, WING Compact, WING Rack | `wing` | UDP 2222 (knock), UDP 2223 (OSC) | `WING?`, `/?`, USB routing, Source and channel names and colors, `/*S` pushes |
| Behringer X-Air (XR18, MR18) | `xair` | UDP 10024 | `/xinfo`, channel and aux return names and colors, USB routing, mix state, preamp gain, Mix Hold settings, `/xremote` pushes |

## Run it

```sh
python3 tools/mixer-sim/mixer_sim.py --scene tools/mixer-sim/scenes/xr18-band.json
python3 tools/mixer-sim/mixer_sim.py --scene tools/mixer-sim/scenes/wing-band.json
```

It prints where it listens, for example `mixer-sim: xair on 0.0.0.0: osc 10024`, then logs every message it receives
and sends to standard error, and runs until Ctrl-C or `quit`.

- `--family NAME`: the family, when the scene doesn't say (`"family"` in the scene).
- `--bind ADDRESS`: listen on one address only (default: all of them). Use the host's LAN address, or 127.0.0.1 for
  tests on the same machine.
- `--port ROLE=N`: listen for a role (`osc`, or the WING's `knock`) on another port; `0` takes any free port. The app
  asks the real ports, so this is for tests and for a second simulator on the same host.
- `--log FILE`: write the log to a file instead; `--quiet`: no log.
- `--control-port N`: also take commands on UDP `127.0.0.1:N` (see "Change the scene live").
- Fault modes: `--discovery-only`, `--delay-ms MS`, `--drop-after S` (see "Change the scene live").
- `--script FILE`: run commands at set times.
- `--subscription-seconds S`: how long `/xremote` or `/*S` lasts unless renewed (default 10, as on the mixers).

### Where to run it

- **This Linux laptop (omarchy-laptop):** Tailscale must be off, or the phone's packets don't reach it. Patrick
  Maillot's WING emulator (wingemul) may already hold UDP 2222 here: while it runs, a WING simulator can't take port
  2222 (`Address already in use`). Use another machine for the WING, or ask before stopping wingemul.
- **hermes** (`ssh hermes`): check out the repo and run the same command. hermes must be on the phone's LAN.
- **A Mac:** the same command with the system `python3`. macOS asks once whether Python may accept incoming network
  connections: allow it.

Eric's test XR18 is on the same LAN (192.168.1.146). Find Mixers then lists both it and the simulator, with their
network names: the scene's is `FOH-XR18`.

## Point the app at it

The phone, iPad or Mac running the app must reach the simulator's host on the LAN: same Wi-Fi or wired network, no
VPN in the way, and the host's firewall open for the family's ports (on Linux with ufw, for example
`sudo ufw allow 10024/udp`; remove the rule when done).

1. Start the simulator on the host and note the host's LAN address (`ip -4 addr` on Linux, `ipconfig getifaddr en0`
   on a Mac).
2. In the app: Settings > Mixer Link > **Find Mixers** lists it (it asks every address on the phone's network), or
   type the host's address in **Mixer IP address** and tap **Connect**.
3. The Stems' names and colors on the record screen come from the scene. Change the scene live (below) and watch them
   follow.

**Mixer Link shows only for a matching audio interface.** The app offers Mixer Link only while the Ready audio
interface's name says it is a mixer of a known family (an XR18, an X32 card, a WING). The built-in microphone and the
Demo signal get no Mixer Link section in Settings. So the simulator is reached from a device with a matching USB audio
interface plugged in. The WING family is offered only in Debug builds for now (`WingAvailability`).

## Change the scene live

Type a command and Enter in the terminal the simulator runs in; it answers `ok`, a value or `error: ...`. Or send
one command per UDP datagram to the control port, which answers the same way, for example from another terminal:

```sh
echo 'name ch/11 Lead Vox 2' | nc -u -w1 127.0.0.1 9999   # started with --control-port 9999
```

| Command | X-Air | WING |
|---|---|---|
| Rename | `name ch/1 Kick In`, `name aux Playback` | `name LCL/1 Kick In` (a Source), `name ch/1 Kick` |
| Recolor | `color ch/1 3` (0-15) | `color LCL/1 5` (1-12) |
| Repatch a USB output | `patch usb 17 26` (source 0-37: 0-15 channels, 16-17 aux, 26-31 buses, ...) | `patch usb 3 LCL/9`, `patch usb 47 MAIN/1`, `patch usb 5 OFF/1` |
| Move a channel's input | `input ch/2 5` (0-17) | |
| Preamp gain | `gain 11 40.5` (headamp 1-18, dB) | |
| Any parameter | `set /ch/03/gate/on 1`, `get /ch/03/gate/on` | |

Every family also takes:

| Command | What it does |
|---|---|
| `discovery-only on` / `off` | Answers discovery (`/xinfo`, the WING knock) and nothing else, as wingemul does over OSC |
| `delay 300` | Sends every reply and push 300 ms late (`delay 0` to stop) |
| `drop` / `resume` | Stops answering anything, as a mixer that drops off the network, and comes back |
| `drop-after 30` | Drops 30 seconds from now |
| `status`, `help` | Where it listens and which faults are on; the commands |

A client subscribed for live updates gets each change pushed, as the mixer would, and so does a change another client
sets over OSC:

- **X-Air:** `/xremote` subscribes the sender for 10 seconds; any number of clients. A set from a client is echoed back
  to it with no arguments, as the XR18 does (firmware 1.26), and pushed to the others.
- **WING:** `/*S` (or `/*s`) on the OSC port subscribes the sender for 10 seconds; only the last client to ask is
  subscribed (WING Remote Protocols, pp. 14 and 28). Text is pushed as `,s`, an integer as `,i` after `/*S` and `,sfi`
  after `/*s`.

A script is a JSON list of commands with the seconds after start each one runs. `scripts/xr18-take.json` and
`scripts/wing-take.json` rename, recolor and repatch during the first minute, then drop off for 15 seconds:

```json
[{"at": 20, "command": "name ch/11 Lead Vox 2"}, {"at": 60, "command": "drop"}, {"at": 75, "command": "resume"}]
```

The log has one line per message, `<-` received and `->` sent, with the peer, the port's role and the OSC address
and arguments (or the text), plus a line per command:

```
14:02:11.120 <- 192.168.1.23:52011 osc /xinfo
14:02:11.120 -> 192.168.1.23:52011 osc /xinfo '192.168.1.40' 'FOH-XR18' 'XR18' '1.26'
14:02:11.300 <- 192.168.1.23:52011 osc /routing/usb/01
14:02:11.300 -> 192.168.1.23:52011 osc /routing/usb/01 0 0
```

## Scenes

A scene is a JSON file in `tools/mixer-sim/scenes/`. They are plain data, so the package's Swift tests can load the
same files as fixtures later (from the repository: `tools/mixer-sim/scenes/<name>.json`).

### X-Air (`scenes/xr18-band.json`)

| Key | Meaning |
|---|---|
| `family` | `"xair"` |
| `network_name`, `model`, `firmware` | What `/xinfo` answers, after the host's own address. `model` `XR18` or `MR18` (18 USB Channels); `XR12`, `XR16` have none. |
| `channels` | `[{"channel": 1, "name": "Kick", "color": 1, "insrc": 0, "on": 1, "fader": 0.75, "usb_return": 0}]`, channels 1-16: `/ch/01/config/name`, `/color` (0-15), `/insrc` (0-15 In01-16, 16-17 aux line in), `/mix/on`, `/mix/fader` (0..1), `/preamp/rtnsw`. Anything left out: no name, color 0, channel n on In n, on, fader 0.75. |
| `aux_return` | `{"name": "Playback", "color": 5, "on": 1, "fader": 0.75}`: `/rtn/aux/...` |
| `usb_routing` | `[{"usb": 18, "source": 26, "tap": 4}]`: `/routing/usb/18`. Default: USB 1-16 on channels 1-16 (source 0-15), 17-18 on the aux return (16-17). |
| `headamps` | `[{"headamp": 1, "gain_db": 32}]`: `/headamp/01/gain`, -12 to +60 dB (1-16) or -12 to +20 dB (17-18). Default 0 dB. |
| `links`, `link_preamps` | `["5-6"]` stereo-links channels 5 and 6 (`/config/chlink/5-6`); `true` links their preamps too (`/config/linkcfg/preamp`). |
| `osc` | `{"/ch/01/gate/on": [1]}`: any address, as is, for a setting the format has no key for. The gate, compressor and sends Mix Hold reads default to off and silent. |
| `remove` | `["/routing/usb/*"]`: leaves those addresses unanswered, as older firmware that doesn't know them. |

### WING (`scenes/wing-band.json`)

| Key | Meaning |
|---|---|
| `family` | `"wing"` |
| `network_name`, `model`, `serial`, `firmware` | The identity the knock and `/?` answer: `WING,<ip>,<name>,<model>,<serial>,<firmware>`. `model` is `ngc-full` (full-size), `wing-compact`, `wing-rack` or `wing-bk`. The IP is the host's own address as the asker sees it. |
| `sources` | `[{"source": "LCL/1", "name": "Kick", "color": 9}]`: each Source's name (`/io/in/LCL/1/name`) and color 1-12 (`/col`). Any Source left out has an empty name and color 1. |
| `usb_outputs` | `[{"usb": 1, "source": "LCL/1"}]`: what USB output 1-48 carries (`/io/out/USB/1/grp` and `/in`). A mix is a group too: `"MAIN/1"`, `"BUS/3"`. Any output left out is `OFF`. |
| `channels` | `[{"channel": 1, "name": "Kick", "color": 9, "input": "LCL/1"}]`: input channels 1-40 (`/ch/1/name`, `/col`, `/in/conn/grp`, `/in/conn/in`). Any channel left out takes `LCL/<its number>` with no name. |

An integer answers as the WING does, `,sfi`: its text, its raw 0 to 1 value and the integer. The WING's preamp gain is
not simulated yet: the app doesn't read it.

An address a scene has no value for gets no answer, on every family.

## Tests

```sh
python3 -B -m unittest discover -s tools/mixer-sim/tests
```

They start the simulator on 127.0.0.1 and free ports (never the real ones, so they run beside wingemul or a real
mixer) and talk to it over real UDP. Every wait has a timeout of a second or less. `scripts/verify.sh` runs them when
`tools/mixer-sim/` changes, and so does CI (the "Mixer Link test bench" job, which the required "Test and build" check
waits for).

## What it does not prove

- **USB audio.** It sends no audio. Whether a mixer's USB interface shows up on an iPhone, iPad or Mac with all its
  channels is checked only with the real mixer.
- **Real-console quirks.** It answers what the app's drivers and the protocol documents say, not what a console does
  when they differ: timing (the XR18's fader easing, #688), replies to odd queries, firmware differences. A value it
  answers is the scene's, not a measured one.
- **The WING** is built from Maillot's WING Remote Protocols document (V3.0.5-1) alone; no real WING has been checked
  against it.
- **The final check stays the real hardware:** Eric's XR18, and a real WING once one is available.
