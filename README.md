# AirRadio v0.1

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
2. A fullscreen static map is painted on `/dev/fb0` with `fbi`.
3. Every 25 s the map service fetches OpenSky traffic in a bounding box,
   overlays up to 40 airborne callsigns, and refreshes the frame.
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
    render-map.sh
    display-once.sh
    update-map.sh
    display-loop.sh
    radio-start.sh
    generate-placeholder-map.sh
    lib.sh
  data/
    aircraft.json
    last-error.log
```

Systemd: `airradio-radio.service`, `airradio-display.service` (long-running
`fbi` — required on vc4 DRM or the screen goes blank), `airradio-map.service`
(oneshot fetch+render), `airradio-map.timer` (`OnBootSec=15s`,
`OnUnitActiveSec=25s`).

## Install on the Pi

From this tree, as root:

```bash
sudo ./install.sh
```

That installs `curl jq imagemagick fbi alsa-utils mpv fonts-dejavu-core`,
copies files to `/opt/airradio`, enables the units, and adds
`consoleblank=0` to the kernel command line if missing.

## Configuration

Edit `/opt/airradio/config.env` (not the scripts).

### Station URL

```bash
RADIO_URL="https://icecast.vrtcdn.be/radio1-high.mp3"
sudo systemctl restart airradio-radio.service
```

v0.1 default is VRT Radio 1 (known-good HTTPS stream). Any Icecast/HTTP
stream `mpv` can play is fine.

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

Projection is linear plate-carrée:

```
x = (lon - MAP_LOMIN) / (MAP_LOMAX - MAP_LOMIN) * width
y = (MAP_LAMAX - lat) / (MAP_LAMAX - MAP_LAMIN) * height
```

`map.png` **must** match the `MAP_*` values. The fetch box can be larger
so traffic near the edge is already in the last-good file.

Default home marker: `50.8950 N, 2.6963 E` (West Flanders). Tune both
boxes if you move.

### OpenSky token

Anonymous access is about 400 requests/day. The 25 s timer is about 3456
requests/day, so anonymous use will hit HTTP 429; the last good overlay
stays on screen.

Register at OpenSky, put a Bearer token in `OPENSKY_TOKEN`, and keep
`POLL_SECONDS` at 25 s (registered allowance is about 4000/day).

The timer interval is **also** hardcoded in
`/etc/systemd/system/airradio-map.timer` as `OnUnitActiveSec=25s`. If you
change the poll, edit the timer and `systemctl daemon-reload`.

Never call `/states/all` without a bbox.

### Map image

Install generates a dark 1920×1080 placeholder with a lat/lon grid, a few
city labels, and a home crosshair.

To use a real map:

1. Export a static PNG covering **exactly** `MAP_*` (OSM export, screenshot,
   GIS render). Prefer a dark / low-contrast style.
2. Same aspect as the HDMI mode if you can (here 1920×1080). Otherwise
   `fbi -a` letterboxes.
3. Copy over `/opt/airradio/map.png`.
4. Do not download tiles at runtime.

Regenerate the placeholder:

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
- `fbi` must run on the HDMI VT (`-T 1`, systemd `TTYPath=/dev/tty1`).
  On vc4 DRM (`vc4drmfb`), killing `fbi` **clears** `/dev/fb0`. The
  display service therefore stays running. Install disables `getty@tty1`
  so the login prompt does not fight `fbi`. Re-enable with
  `sudo systemctl enable --now getty@tty1` if you need a local console.
- Overlay cap is 40 aircraft, nearest map centre first, airborne only
  (`SKIP_GROUND=1`).

## Out of scope (v0.1)

RTL-SDR / dump1090, Python rewrite, zoom/pan, ATC audio, preset UI,
browser kiosk.
