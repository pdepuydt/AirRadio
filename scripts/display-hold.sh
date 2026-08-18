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

if ! "${AIRRADIO_ROOT}/scripts/blit-frame.sh" "${FRAME_OUT}" "${FB_DEVICE}"; then
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
    if [ "${now_mtime}" = "${last_mtime}" ]; then
        continue
    fi
    last_mtime="${now_mtime}"
    "${AIRRADIO_ROOT}/scripts/blit-frame.sh" "${FRAME_OUT}" "${FB_DEVICE}" || log_err "framebuffer blit failed"
done
