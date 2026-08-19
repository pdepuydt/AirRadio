# Shared helpers. Sourced by other scripts. Not executed.

AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/config.env"
# Written by fetch-basemap.sh so overlay bounds match the Google image.
if [ -f "${AIRRADIO_ROOT}/map.extent.env" ]; then
    # shellcheck disable=SC1091
    . "${AIRRADIO_ROOT}/map.extent.env"
fi

DATA_DIR="${AIRRADIO_ROOT}/data"
AIRCRAFT_JSON="${DATA_DIR}/aircraft.json"
ROUTES_JSON="${DATA_DIR}/routes.json"
ERROR_LOG="${DATA_DIR}/last-error.log"

log_err() {
    local line
    line="$(date -Is) $*"
    mkdir -p "${DATA_DIR}"
    echo "${line}" >> "${ERROR_LOG}"
    if [ "$(wc -c < "${ERROR_LOG}")" -gt 102400 ]; then
        tail -n 80 "${ERROR_LOG}" > "${ERROR_LOG}.tmp" && mv "${ERROR_LOG}.tmp" "${ERROR_LOG}"
    fi
    echo "${line}" >&2
}

im_convert() {
    if command -v convert >/dev/null 2>&1; then
        convert "$@"
    elif command -v magick >/dev/null 2>&1; then
        magick convert "$@"
    else
        echo "ImageMagick convert/magick not found" >&2
        return 127
    fi
}

im_identify() {
    if command -v identify >/dev/null 2>&1; then
        identify "$@"
    elif command -v magick >/dev/null 2>&1; then
        magick identify "$@"
    else
        echo "ImageMagick identify not found" >&2
        return 127
    fi
}
