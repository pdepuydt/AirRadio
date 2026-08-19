#!/bin/bash
# Fetch OpenSky states for the configured bbox. Keep last good file on failure.
# Registered access: OAuth2 client credentials → Bearer token (cached ~30 min).
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

mkdir -p "${DATA_DIR}"

TOKEN_URL="${OPENSKY_TOKEN_URL:-https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token}"
TOKEN_CACHE="${DATA_DIR}/opensky-token.json"
TOKEN_MARGIN="${OPENSKY_TOKEN_MARGIN:-30}"

tmp="$(mktemp "${DATA_DIR}/aircraft.json.XXXXXX")"
hdr="$(mktemp "${DATA_DIR}/aircraft.hdr.XXXXXX")"
cleanup() { rm -f "${tmp}" "${hdr}"; }
trap cleanup EXIT

cached_token_fresh() {
    [ -f "${TOKEN_CACHE}" ] || return 1
    jq -e --argjson now "$(date +%s)" --argjson margin "${TOKEN_MARGIN}" \
        '.access_token != null and .access_token != "" and ((.expires_at | tonumber) > ($now + $margin))' \
        "${TOKEN_CACHE}" >/dev/null 2>&1
}

request_token() {
    local body code
    body="$(mktemp "${DATA_DIR}/opensky-token.XXXXXX")"
    if ! code="$(curl -sS -o "${body}" -w '%{http_code}' --max-time 20 \
        -X POST "${TOKEN_URL}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=${OPENSKY_CLIENT_ID}" \
        --data-urlencode "client_secret=${OPENSKY_CLIENT_SECRET}")"; then
        rm -f "${body}"
        log_err "opensky token curl failed"
        return 1
    fi
    if [ "${code}" != "200" ]; then
        log_err "opensky token HTTP ${code}"
        rm -f "${body}"
        return 1
    fi
    if ! jq -e '.access_token and .access_token != ""' "${body}" >/dev/null 2>&1; then
        log_err "opensky token response missing access_token"
        rm -f "${body}"
        return 1
    fi
    jq -c --argjson now "$(date +%s)" \
        '{access_token: .access_token, expires_at: ($now + ((.expires_in // 1800) | tonumber))}' \
        "${body}" > "${TOKEN_CACHE}.partial"
    chmod 600 "${TOKEN_CACHE}.partial"
    mv "${TOKEN_CACHE}.partial" "${TOKEN_CACHE}"
    rm -f "${body}"
}

load_bearer() {
    bearer=""
    if [ -n "${OPENSKY_CLIENT_ID:-}" ] && [ -n "${OPENSKY_CLIENT_SECRET:-}" ]; then
        if ! cached_token_fresh; then
            request_token || return 1
        fi
        bearer="$(jq -r '.access_token // empty' "${TOKEN_CACHE}" 2>/dev/null || true)"
        if [ -z "${bearer}" ]; then
            log_err "opensky registered auth failed"
            return 1
        fi
    elif [ -n "${OPENSKY_TOKEN:-}" ]; then
        bearer="${OPENSKY_TOKEN}"
    fi
}

fetch_states() {
    local auth=()
    if [ -n "${bearer}" ]; then
        auth=(-H "Authorization: Bearer ${bearer}")
    fi
    curl -sS -o "${tmp}" -D "${hdr}" -w '%{http_code}' --max-time 20 \
        "${auth[@]}" \
        --get "${OPENSKY_URL}" \
        --data-urlencode "lamin=${LAMIN}" \
        --data-urlencode "lamax=${LAMAX}" \
        --data-urlencode "lomin=${LOMIN}" \
        --data-urlencode "lomax=${LOMAX}"
}

bearer=""
if ! load_bearer; then
    exit 0
fi

code="000"
if ! code="$(fetch_states)"; then
    log_err "opensky curl failed"
    exit 0
fi

if [ "${code}" = "401" ] && [ -n "${OPENSKY_CLIENT_ID:-}" ] && [ -n "${OPENSKY_CLIENT_SECRET:-}" ]; then
    rm -f "${TOKEN_CACHE}"
    if load_bearer; then
        if ! code="$(fetch_states)"; then
            log_err "opensky curl failed after token refresh"
            exit 0
        fi
    fi
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
rm -f "${hdr}"
exit 0
