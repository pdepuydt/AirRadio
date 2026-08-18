#!/bin/bash
# Show FRAME_OUT on the HDMI framebuffer once. Leaves the pixels on /dev/fb0.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

if [ ! -f "${FRAME_OUT}" ]; then
    log_err "no frame to display: ${FRAME_OUT}"
    exit 0
fi

tty_dev="/dev/tty${FBI_TTY}"
if [ -w "${tty_dev}" ]; then
    setterm --blank 0 --powersave off <"${tty_dev}" >"${tty_dev}" 2>/dev/null || true
fi

# Manual one-shot helper. On vc4 DRM the picture only stays if fbi is left
# running — prefer display-hold.sh / airradio-display.service.
publish_slots "${FRAME_OUT}" || true
if systemctl is-active --quiet airradio-display.service 2>/dev/null; then
    exit 0
fi
exec "${AIRRADIO_ROOT}/scripts/display-hold.sh"
