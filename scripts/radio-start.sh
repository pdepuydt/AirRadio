#!/bin/bash
# mpv wrapper → HDMI ALSA. Restart policy lives in systemd.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

if [ -z "${RADIO_URL:-}" ]; then
    log_err "RADIO_URL is empty"
    exit 1
fi

exec mpv --no-video --ao=alsa \
    --audio-device="alsa/${RADIO_ALSA}" \
    --volume="${RADIO_VOLUME}" \
    --loop-playlist=inf \
    --cache=yes --cache-secs=10 \
    --network-timeout=15 \
    --script="${AIRRADIO_ROOT}/scripts/mpv-nowplaying.lua" \
    "${RADIO_URL}"
