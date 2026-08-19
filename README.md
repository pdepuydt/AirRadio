# AirRadio v0.6

Always-on HDMI companion for a Raspberry Pi Zero W: internet radio on HDMI
audio, nearby aircraft on a static map via the framebuffer. No Python, no
desktop, no SDR.

Personal non-commercial OpenSky use only (their ToS).

## Hardware target

- Raspberry Pi Zero W (original, ARMv6 / 32-bit userland)
- Raspberry Pi OS Lite Bookworm (`armhf`)
- Mini-HDMI for **video and audio**
- Solid 5 V / 2 A+ supply

## What it does

On boot:

1. `mpv` starts the configured stream on the HDMI ALSA device and restarts
   on failure.
2. A fullscreen static map is written directly to `/dev/fb0` (RGB565).
   A top bar shows the time and date (once a minute); a bottom ticker
   shows the station and track when that text changes.
3. Every 25 s the map service fetches OpenSky traffic in a bounding box,
   overlays up to 40 airborne aircraft with IATA origin–destination
   (`LHR - BRU`) when known, otherwise the callsign, and refreshes the
   frame.
4. A failed fetch keeps the last good JSON and the last painted frame.
   Radio and map retry independently.

## Layout

```
/opt/airradio/
  VERSION
  config.env
  map.png
  scripts/
    fetch-overlay.sh
    fetch-routes.sh
    render-map.sh
    hud-bars.sh
    display-hold.sh
    blit-frame.sh
    rgb24-to-fb16
    update-map.sh
    radio-start.sh
    mpv-nowplaying.lua
    generate-placeholder-map.sh
    fetch-basemap.sh
    lib.sh
  data/
    aircraft.json
    last-error.log
```

Systemd: `airradio-radio.service`, `airradio-display.service` (unbinds
fbcon and blits complete RGB565 frames to `/dev/fb0`), `airradio-map.service`
(oneshot fetch+render), `airradio-map.timer` (`OnBootSec=15s`,
`OnUnitActiveSec=25s`).

## Install on the Pi

From this tree, as root:

```bash
sudo ./install.sh
```

That installs `curl jq imagemagick alsa-utils mpv fonts-dejavu-core gcc`,
builds `rgb24-to-fb16`, copies files to `/opt/airradio`, enables the units,
and adds `consoleblank=0` to the kernel command line if missing.

## Configuration

Edit `/opt/airradio/config.env` (not the scripts).

### Station URL

```bash
RADIO_URL="https://playerservices.streamtheworld.com/api/livestream-redirect/NOSTALGIEWHATAFEELING.mp3"
sudo systemctl restart airradio-radio.service
```

Default is Nostalgie Vlaanderen (Play Nostalgie). Any Icecast/HTTP stream
`mpv` can play is fine.

### HDMI audio device

This Pi reports `vc4hdmi`:

```
RADIO_ALSA="hdmi:CARD=vc4hdmi,DEV=0"
```

If you switch to legacy firmware KMS the card is often `b1`:

```
RADIO_ALSA="hdmi:CARD=b1,DEV=0"
```

Discover with `aplay -l` and `cat /proc/asound/cards`.

Recommended `/boot/firmware/config.txt` (or `/boot/config.txt`) when HDMI
audio is missing:

```
dtparam=audio=on
hdmi_force_hotplug=1
hdmi_drive=2
```

On current Bookworm + `vc4-kms-v3d` those `hdmi_*` lines are often ignored;
the ALSA card name is the switch that matters.

### Bounding box and map extent

Two boxes:

| Vars | Meaning |
|---|---|
| `LAMIN` `LAMAX` `LOMIN` `LOMAX` | OpenSky query (~100 km) |
| `MAP_LAMIN` `MAP_LAMAX` `MAP_LOMIN` `MAP_LOMAX` | Geographic extent of `map.png` (~75 km) |

Projection matches Google Static Maps: linear longitude, Web Mercator
latitude.

`map.png` **must** match the `MAP_*` values. The fetch box can be larger
so traffic near the edge is already in the last-good file.

Default home marker: `50.8950 N, 2.6963 E` (West Flanders). Tune both
boxes if you move.

### OpenSky token

Anonymous access is about 400 requests/day. The 25 s timer is about 3456
requests/day, so anonymous use will hit HTTP 429; the last good overlay
stays on screen.

Register at [OpenSky](https://opensky-network.org/login?view=registration),
open [Account](https://opensky-network.org/my-opensky/account), create an
API client, and put `clientId` / `clientSecret` in `OPENSKY_CLIENT_ID` and
`OPENSKY_CLIENT_SECRET`. `fetch-overlay.sh` exchanges those for a Bearer
token and refreshes it before it expires (~30 min). Keep `POLL_SECONDS`
at 25 s (registered allowance is about 4000/day).

Do not put a one-shot Bearer token in `OPENSKY_TOKEN` unless you are
testing — it expires. Username/password basic auth was retired in March
2026.

The timer interval is **also** hardcoded in
`/etc/systemd/system/airradio-map.timer` as `OnUnitActiveSec=25s`. If you
change the poll, edit the timer and `systemctl daemon-reload`.

Never call `/states/all` without a bbox.

### Map image

`map.png` is meant to be **Google Maps Terrain** from the official Static
Maps API. Set `GOOGLE_MAPS_API_KEY` in `config.env` (Maps Static API
enabled on a billed GCP project), then:

```bash
sudo AIRRADIO_ROOT=/opt/airradio /opt/airradio/scripts/fetch-basemap.sh
sudo systemctl start airradio-map.service
```

That writes `map.png` plus `map.extent.env` (the real lat/lon of the
image) so aircraft stay on the roads.

Refresh the shipped basemap (install-time / operator, not every poll):

```bash
sudo AIRRADIO_ROOT=/opt/airradio /opt/airradio/scripts/fetch-basemap.sh
sudo systemctl start airradio-map.service
```

Or drop any 1920×1080 PNG of the same lat/lon extent over
`/opt/airradio/map.png`. Do not download tiles at runtime.

Placeholder grid instead of OSM:

```bash
sudo AIRRADIO_ROOT=/opt/airradio /opt/airradio/scripts/generate-placeholder-map.sh
```

## Logs

```bash
journalctl -u airradio-radio.service -f
journalctl -u airradio-map.service -f
tail -f /opt/airradio/data/last-error.log
```

## Zero W limits

- 512 MB RAM, ARMv6: stay on 32-bit packages. ImageMagick on a 1920×1080
  frame plus 40 labels can take several seconds; the timer budget is 90 s.
- Wi-Fi drops: radio `Restart=always`; map keeps last JSON/frame.
- Display unbinds fbcon (`/sys/class/vtconsole/vtcon1/bind`) and writes
  a full 1920×1080 RGB565 frame to `/dev/fb0`. No `fbi`. Stopping the
  display service rebinds the console. Install disables `getty@tty1`.
  Re-enable with `sudo systemctl enable --now getty@tty1` if you need a
  local console.
- Overlay cap is 40 aircraft, nearest map centre first, airborne only
  (`SKIP_GROUND=1`).

## Out of scope (later)

RTL-SDR / dump1090, Python rewrite, zoom/pan, ATC audio, preset UI,
browser kiosk.
