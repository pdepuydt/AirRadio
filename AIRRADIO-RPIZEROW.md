# AirRadio — Raspberry Pi Zero W

Hand this file to Grok Build. Implement on Raspberry Pi OS Lite (Bookworm/Trixie, 32-bit recommended for original Pi Zero W).

**Goal:** Always-on HDMI companion that plays a standard internet-radio station **and** shows nearby aircraft as a data overlay on a **static map**. No Python. No SDR in this phase.

Status: idea specified; hardware target is a Pi Zero W that is already up.

---

## Hardware

- Raspberry Pi Zero W (original, BCM2835, 512 MB)
- Mini-HDMI → TV / monitor / AV receiver (video **and** audio)
- Power: solid 5 V / 2 A+ (Wi-Fi + HDMI + decode)
- No extra HAT, no RTL-SDR, no analog jack

Keep memory and CPU low. No desktop environment.

---

## Product behaviour

On boot:

1. HDMI audio starts the configured internet-radio stream (loop / auto-restart).
2. HDMI video shows a fullscreen static map of the home area.
3. Every N seconds (default 20–30), aircraft positions from OpenSky are overlaid (callsign + altitude).
4. If the fetch fails, keep the last good overlay and do not crash the radio.

Ambient desk/TV device. Not a flight-radar workstation.

---

## Hard constraints

- **No Python** anywhere in the runtime path.
- No X11 / Wayland / full desktop.
- Tools only: bash, curl, jq, ImageMagick (`convert`), fbi, and a radio player (`mpv` preferred; MPD+mpc acceptable).
- OpenSky **bounding box** on every request (never `/states/all` unfiltered).
- Poll interval must respect OpenSky credits (anonymous ~400/day; registered ~4000/day). Default ≥ 20 s.
- All paths and secrets in config files, not hardcoded in scripts.LAMIN=50.00
LAMAX=51.79
LOMIN=0.16
LOMAX=5.23
- Survive Wi-Fi blips: radio and map each retry independently.

---

## Software stack

| Role | Tool |
|---|---|
| OS | Raspberry Pi OS Lite, 32-bit |
| Radio | `mpv` (or `mpd` + `mpc`) → HDMI ALSA device |
| Fetch | `curl` |
| Parse | `jq` |
| Overlay | ImageMagick `convert` |
| Display | `fbi` on `/dev/fb0` |
| Init | systemd units (two services + one timer or loop) |

Optional later: lighttpd + static HTML if fbi proves awkward. First implementation = framebuffer.

---

## Directory layout

```
/opt/airradio/
  config.env                 # station URL, bbox, poll, paths
  map.png                    # static background (user-supplied)
  scripts/
    fetch-overlay.sh         # curl + jq → aircraft.json
    render-map.sh            # convert map.png + json → /tmp/airradio-frame.png
    display-loop.sh          # fbi refresh loop (or oneshot + timer)
    radio-start.sh           # mpv wrapper
  data/
    aircraft.json            # last good fetch
    last-error.log
/etc/systemd/system/
  airradio-radio.service
  airradio-map.service
  airradio-map.timer         # if using oneshot instead of a sleep loop
```

User home copies of configs are fine during development; install target is `/opt/airradio`.

---

## Configuration (`config.env`)

```bash
# Radio
RADIO_URL="https://icecast.example/stream"   # replace with real station
RADIO_ALSA="hdmi:CARD=b1,DEV=0"              # discover with aplay -l / cat /proc/asound/cards
RADIO_VOLUME=80

# OpenSky
OPENSKY_URL="https://opensky-network.org/api/states/all"
# West Flanders / Flanders-ish default — tune to the actual site
# 50.8950° N, 2.6963° E -> Home
# A 100km radius HD optimised
LAMIN=50.00
LAMAX=51.79
LOMIN=0.16
LOMAX=5.23
# A 75km Radius
MAP_LAMIN=50.22
MAP_LAMAX=51.57
MAP_LOMIN=0.80
MAP_LOMAX=4.60
# Original
#LAMIN=50.60
#LAMAX=51.40
#LOMIN=2.40
#LOMAX=3.95

POLL_SECONDS=25

# Optional OAuth2 (registered account). Leave empty for anonymous.
OPENSKY_TOKEN=""
# If token flow is used later: client id/secret + token cache file.

# Map
MAP_SRC="/opt/airradio/map.png"
FRAME_OUT="/tmp/airradio-frame.png"
# Geographic extent of MAP_SRC (must match the image)
LAMIN=50.00
LAMAX=51.79
LOMIN=0.16
LOMAX=5.23
#Original
#MAP_LAMIN=50.60
#MAP_LAMAX=51.40
#MAP_LOMIN=2.40
#MAP_LOMAX=3.95

# Display
FB_DEVICE="/dev/fb0"
FBI_TTY=1
```

The map image extent **must** match the bbox used for projection. Document how to generate `map.png` (OSM static export, screenshot, or any PNG). Equirectangular / plate-carrée assumption is enough: linear lat/lon → pixel.

---

## OpenSky request

GET with query params:

```
lamin LAMIN  lomin LOMIN  lamax LAMAX  lomax LOMAX
```

If `OPENSKY_TOKEN` is set:

```
Authorization: Bearer $OPENSKY_TOKEN
```

Save raw JSON to `data/aircraft.json` only on HTTP 200. On 429 / network error: keep previous file, log, exit 0 so systemd does not flap.

`jq` extract (state vector index — do not invent field names):

| Index | Field |
|---|---|
| 0 | icao24 |
| 1 | callsign |
| 5 | lon |
| 6 | lat |
| 7 | baro altitude (m) |
| 9 | on_ground |
| 10 | velocity |
| 11 | true_track |

Skip states with null lat/lon or `on_ground == true` (optional filter; make it a config flag `SKIP_GROUND=1`).

---

## Projection (static overlay)

Linear mapping:

```
x = (lon - MAP_LOMIN) / (MAP_LOMAX - MAP_LOMIN) * width
y = (MAP_LAMAX - lat) / (MAP_LAMAX - MAP_LAMIN) * height
```

ImageMagick per aircraft (batch in one `convert` if possible to avoid many process starts):

- Small filled circle or triangle at (x,y)
- Label: trimmed callsign + altitude in feet (`alt_m * 3.28084`)
- Colour by altitude bands (e.g. < FL100, FL100–FL250, > FL250)

Cap overlays (e.g. max 40 aircraft, nearest to map centre first) so the Zero W stays responsive.

Write atomically: render to `FRAME_OUT.tmp` then `mv`.

---

## fbi display

- Raspberry Pi OS Lite, console on HDMI.
- `fbi -T $FBI_TTY -d $FB_DEVICE -a -noverbose --once $FRAME_OUT` for oneshot, **or**
- A documented trick to refresh without a long black flash (two symlinks + `-cachemem 0` + timed loop, as commonly used on Pi).

Prefer a systemd oneshot + timer that:

1. fetch
2. render
3. fbi once

over an infinite bash `while` if it is more reliable. Either is acceptable; pick the one that does not blank the screen for seconds.

`fbi` needs the right TTY when started from systemd (`-T 1` typical). Test both local console and ssh.

---

## HDMI audio (radio)

Pi Zero W has no 3.5 mm jack. Force HDMI:

`/boot/firmware/config.txt` (or `/boot/config.txt`):

```
dtparam=audio=on
hdmi_force_hotplug=1
hdmi_drive=2
# hdmi_force_edid_audio=1   # only if the sink does not advertise audio
```

Discover the card:

```
aplay -l
cat /proc/asound/cards
```

`mpv` example:

```
mpv --no-video --ao=alsa --audio-device=alsa/$RADIO_ALSA \
    --volume=$RADIO_VOLUME --loop-playlist=inf \
    --cache=yes --cache-secs=10 \
    "$RADIO_URL"
```

systemd: `Restart=always`, `RestartSec=5`. Network-online dependency.

If HDMI device name changes between `b1` and `vc4hdmi`, document both and make `RADIO_ALSA` the single switch.

---

## systemd

**airradio-radio.service** — long-running mpv.

**airradio-map.service** — oneshot: fetch + render + fbi.

**airradio-map.timer** — `OnBootSec=15s`, `OnUnitActiveSec=${POLL_SECONDS}`.

Enable both. Do not let map failures stop radio.

Logging: journald. Extra errors to `data/last-error.log`.

---

## Packages to install

```
sudo apt-get update
sudo apt-get install -y \
  curl jq imagemagick fbi alsa-utils mpv \
  fonts-dejavu-core
```

No Python packages. No Node. No browser kiosk in v1.

---

## Map asset

Ship a placeholder `map.png` **or** a short README section:

1. Export a static map covering the same lat/lon as `MAP_*`.
2. Same aspect as the HDMI mode if possible (or letterbox in `convert`).
3. Dark / low-contrast style so white/yellow labels stay readable.
4. Optional: draw a home-location crosshair once into the base image.

Do not download tiles at runtime.

---

## Implementation order for Grok Build

1. Confirm OS, HDMI video, HDMI audio test tone (`speaker-test` / `aplay`).
2. `config.env` + directory layout.
3. Radio service with a placeholder URL; user replaces it.
4. `fetch-overlay.sh` with bbox + last-good-file behaviour.
5. `render-map.sh` with linear projection + labels.
6. fbi oneshot + timer.
7. Boot enable, README with:
   - how to set station URL
   - how to set bbox and map extent
   - how to register OpenSky and add a token later
   - how to read logs
   - known Zero W limits (RAM, Wi-Fi, fbi TTY)

Do not implement SDR, Mopidy, Chromium kiosk, or Python “just in case”.

---

## Acceptance checks

- After reboot, radio plays on HDMI without login.
- After reboot, map appears on HDMI without login.
- Aircraft appear as overlay when OpenSky returns traffic in the bbox.
- Pulling Wi-Fi briefly: radio recovers; map keeps last frame.
- `free -h` stays sane (no leak from convert/fbi).
- No Python interpreter required at runtime (`pgrep python` empty).

---

## Out of scope (later)

- RTL-SDR / dump1090 local receive
- Python rewrite
- Interactive zoom/pan
- ATC audio
- Multiple radio presets UI (a simple `RADIO_URL` file is enough for v1)
- 64-bit OS / Zero 2 W-only features (Zero 2 W should still run this as-is)

---

## Notes for the implementer

- Original Pi Zero W is ARMv6: use 32-bit userland; avoid packages that are arm64-only.
- ImageMagick 6 vs 7: `convert` vs `magick` — detect and use what the OS ships.
- OpenSky field order is a positional array; do not treat states as objects.
- Cite/use OpenSky only for personal non-commercial display (their ToS).
- User locale: Belgium (West Flanders). Default bbox is a starting point, not a locked home coordinate.

When in doubt: smaller, more reliable, fewer moving parts.
