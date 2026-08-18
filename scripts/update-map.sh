#!/bin/bash
# One cycle: fetch → render → display. Always exit 0 so systemd does not flap.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

"${AIRRADIO_ROOT}/scripts/fetch-overlay.sh" || log_err "fetch-overlay.sh exited $?"
"${AIRRADIO_ROOT}/scripts/render-map.sh" || log_err "render-map.sh exited $?"

if [ ! -f "${FRAME_OUT}" ] && [ -f "${MAP_SRC}" ]; then
    cp -f "${MAP_SRC}" "${FRAME_OUT}" || log_err "cannot seed ${FRAME_OUT}"
fi
if [ -f "${FRAME_OUT}" ]; then
    publish_slots "${FRAME_OUT}" || log_err "cannot publish display slots"
fi
exit 0
