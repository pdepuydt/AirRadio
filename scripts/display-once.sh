#!/bin/bash
# Manual one-shot: paint FRAME_OUT onto /dev/fb0.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"
exec "${AIRRADIO_ROOT}/scripts/blit-frame.sh" "${FRAME_OUT}" "${FB_DEVICE}"
