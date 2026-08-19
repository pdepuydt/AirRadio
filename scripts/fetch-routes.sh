#!/bin/bash
# Look up origin-destination IATA codes for aircraft callsigns (adsbdb).
# Cached. Unknown / GA / military keep the flight number on the map.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

mkdir -p "${DATA_DIR}"

ROUTE_API="${ROUTE_API:-https://api.adsbdb.com/v0/callsign}"
MAX_LOOKUPS="${ROUTE_LOOKUPS_PER_CYCLE:-4}"
OK_TTL="${ROUTE_OK_TTL:-43200}"
FAIL_TTL="${ROUTE_FAIL_TTL:-21600}"

if [ ! -f "${AIRCRAFT_JSON}" ]; then
    exit 0
fi
if [ ! -f "${ROUTES_JSON}" ]; then
    echo '{}' > "${ROUTES_JSON}"
    chmod 644 "${ROUTES_JSON}"
fi

now="$(date +%s)"
need="$(jq -r --argjson now "${now}" --argjson okttl "${OK_TTL}" --argjson failttl "${FAIL_TTL}" \
    --slurpfile cache "${ROUTES_JSON}" '
    ($cache[0] // {}) as $c
    | (.states // [])
    | map((.[1] // "") | gsub("^\\s+|\\s+$";""))
    | unique
    | map(select(test("^[A-Z0-9]{3,8}$")))
    | map(select(
        ($c[.] == null)
        or (
          ($now - (($c[.].ts // 0) | tonumber))
          > (if $c[.].ok == true then $okttl else $failttl end)
        )
      ))
    | .[]
    ' "${AIRCRAFT_JSON}" 2>/dev/null || true)"

[ -n "${need}" ] || exit 0

lookups=0
tmp="$(mktemp "${DATA_DIR}/route-body.XXXXXX")"
cleanup() { rm -f "${tmp}"; }
trap cleanup EXIT

while IFS= read -r cs; do
    [ -n "${cs}" ] || continue
    [ "${lookups}" -lt "${MAX_LOOKUPS}" ] || break
    lookups=$((lookups + 1))

    code="000"
    if ! code="$(curl -sS -o "${tmp}" -w '%{http_code}' --max-time 8 \
        -A "AirRadio/0.6 (personal HDMI companion)" \
        "${ROUTE_API}/${cs}")"; then
        continue
    fi

    orig=""
    dest=""
    ok="false"
    if [ "${code}" = "200" ]; then
        orig_iata="$(jq -r '.response.flightroute.origin.iata_code // empty' "${tmp}" 2>/dev/null || true)"
        dest_iata="$(jq -r '.response.flightroute.destination.iata_code // empty' "${tmp}" 2>/dev/null || true)"
        orig_icao="$(jq -r '.response.flightroute.origin.icao_code // empty' "${tmp}" 2>/dev/null || true)"
        dest_icao="$(jq -r '.response.flightroute.destination.icao_code // empty' "${tmp}" 2>/dev/null || true)"
        if [ -n "${orig_iata}" ] && [ -n "${dest_iata}" ]; then
            orig="${orig_iata}"
            dest="${dest_iata}"
            ok="true"
        elif [ -n "${orig_icao}" ] && [ -n "${dest_icao}" ]; then
            orig="${orig_icao}"
            dest="${dest_icao}"
            ok="true"
        fi
    fi

    route=""
    if [ "${ok}" = "true" ]; then
        route="${orig} - ${dest}"
    fi

    jq --arg cs "${cs}" --arg route "${route}" --arg orig "${orig}" --arg dest "${dest}" \
        --argjson now "${now}" --argjson ok "${ok}" \
        '.[$cs] = {ok: $ok, route: $route, orig: $orig, dest: $dest, ts: $now}' \
        "${ROUTES_JSON}" > "${ROUTES_JSON}.partial" \
        && mv "${ROUTES_JSON}.partial" "${ROUTES_JSON}"
    chmod 644 "${ROUTES_JSON}"
done <<< "${need}"

exit 0
