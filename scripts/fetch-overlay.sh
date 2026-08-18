#!/bin/bash
# Fetch OpenSky states for the configured bbox. Keep last good file on failure.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

mkdir -p "${DATA_DIR}"

tmp="$(mktemp "${DATA_DIR}/aircraft.json.XXXXXX")"
cleanup() { rm -f "${tmp}"; }
trap cleanup EXIT

auth=()
if [ -n "${OPENSKY_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer ${OPENSKY_TOKEN}")
fi

code="000"
if ! code="$(curl -sS -o "${tmp}" -w '%{http_code}' --max-time 20 \
    "${auth[@]}" \
    --get "${OPENSKY_URL}" \
    --data-urlencode "lamin=${LAMIN}" \
    --data-urlencode "lamax=${LAMAX}" \
    --data-urlencode "lomin=${LOMIN}" \
    --data-urlencode "lomax=${LOMAX}")"; then
    log_err "opensky curl failed"
    exit 0
fi

if [ "${code}" != "200" ]; then
    log_err "opensky HTTP ${code}"
    exit 0
fi

if ! jq -e 'type == "object" and has("states")' "${tmp}" >/dev/null 2>&1; then
    log_err "opensky response missing states"
    exit 0
fi

mv "${tmp}" "${AIRCRAFT_JSON}"
chmod 644 "${AIRCRAFT_JSON}"
trap - EXIT
exit 0
