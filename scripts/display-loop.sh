#!/bin/bash
# Optional long-running alternative to the systemd timer.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

poll="${POLL_SECONDS:-25}"
if [ "${poll}" -lt 20 ]; then
    poll=20
fi

while true; do
    "${AIRRADIO_ROOT}/scripts/update-map.sh"
    sleep "${poll}"
done
