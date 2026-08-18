# Shared helpers. Sourced by other scripts. Not executed.

AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/config.env"

DATA_DIR="${AIRRADIO_ROOT}/data"
AIRCRAFT_JSON="${DATA_DIR}/aircraft.json"
ERROR_LOG="${DATA_DIR}/last-error.log"
SLOT_A="${SLOT_A:-/tmp/airradio-slot-a.png}"
SLOT_B="${SLOT_B:-/tmp/airradio-slot-b.png}"

# fbi on vc4 DRM only keeps the picture while it holds the VT.
# Publish two slots so a long-running fbi -t can reread without exiting.
publish_slots() {
    local src="${1:-${FRAME_OUT}}"
    if [ ! -f "${src}" ]; then
        return 1
    fi
    cp -f "${src}" "${SLOT_A}.partial.png" && mv -f "${SLOT_A}.partial.png" "${SLOT_A}"
    cp -f "${src}" "${SLOT_B}.partial.png" && mv -f "${SLOT_B}.partial.png" "${SLOT_B}"
}

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
