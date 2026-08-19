#!/bin/bash
# Own the HDMI framebuffer: unbind fbcon, blit complete frames to /dev/fb0.
# No fbi — starting/stopping it left torn or stale pictures on vc4 DRM.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

fbcon_bind="/sys/class/vtconsole/vtcon1/bind"

unbind_fbcon() {
    if [ -w "${fbcon_bind}" ]; then
        echo 0 >"${fbcon_bind}" || true
    fi
}

rebind_fbcon() {
    if [ -w "${fbcon_bind}" ]; then
        echo 1 >"${fbcon_bind}" || true
    fi
}

if [ ! -f "${FRAME_OUT}" ] && [ -f "${MAP_SRC}" ]; then
    cp -f "${MAP_SRC}" "${FRAME_OUT}" || true
fi
if [ ! -f "${FRAME_OUT}" ]; then
    log_err "no map or frame to display"
    exit 1
fi

pkill -x fbi 2>/dev/null || true
unbind_fbcon
trap rebind_fbcon EXIT TERM INT

nowplaying_file="${NOWPLAYING_FILE:-/tmp/airradio-nowplaying.txt}"

read_track() {
    if [ -f "${nowplaying_file}" ]; then
        tr -d '\r\n' < "${nowplaying_file}"
    fi
}

paint_hud() {
    "${AIRRADIO_ROOT}/scripts/hud-bars.sh" "${1:-all}" || true
}

paint() {
    "${AIRRADIO_ROOT}/scripts/blit-frame.sh" "${FRAME_OUT}" "${FB_DEVICE}" || return 1
    paint_hud all
    last_clock="$(date '+%Y-%m-%dT%H:%M')"
    last_track="$(read_track)"
}

if ! paint; then
    log_err "initial framebuffer blit failed"
    exit 1
fi

last_mtime="$(stat -c %Y "${FRAME_OUT}" 2>/dev/null || echo 0)"

while true; do
    sleep 1
    if [ ! -f "${FRAME_OUT}" ]; then
        continue
    fi
    now_mtime="$(stat -c %Y "${FRAME_OUT}" 2>/dev/null || echo 0)"
    if [ "${now_mtime}" != "${last_mtime}" ]; then
        last_mtime="${now_mtime}"
        paint || log_err "framebuffer blit failed"
        continue
    fi
    now_clock="$(date '+%Y-%m-%dT%H:%M')"
    if [ "${now_clock}" != "${last_clock}" ]; then
        last_clock="${now_clock}"
        paint_hud top
    fi
    now_track="$(read_track)"
    if [ "${now_track}" != "${last_track}" ]; then
        last_track="${now_track}"
        paint_hud bot
    fi
done
