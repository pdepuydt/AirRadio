#!/bin/bash
# Project last-good aircraft.json onto map.png. Atomic write to FRAME_OUT.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

if [ ! -f "${MAP_SRC}" ]; then
    log_err "map source missing: ${MAP_SRC}"
    exit 0
fi

tmp="${FRAME_OUT}.partial.png"
mkdir -p "$(dirname "${FRAME_OUT}")"

if [ ! -f "${AIRCRAFT_JSON}" ]; then
    if ! cp -f "${MAP_SRC}" "${tmp}" || ! mv -f "${tmp}" "${FRAME_OUT}"; then
        log_err "failed to copy map to ${FRAME_OUT}"
    fi
    exit 0
fi

size="$(im_identify -format '%w %h' "${MAP_SRC}" 2>/dev/null)" || size=""
if [ -z "${size}" ]; then
    log_err "cannot identify ${MAP_SRC}"
    exit 0
fi
# shellcheck disable=SC2086
set -- ${size}
width="$1"
height="$2"

skip="${SKIP_GROUND:-1}"
max="${MAX_AIRCRAFT:-40}"
font="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"

draw_file="$(mktemp /tmp/airradio-draw.XXXXXX)"
cleanup() { rm -f "${draw_file}" "${tmp}"; }
trap cleanup EXIT

if ! jq -r \
    --argjson w "${width}" \
    --argjson h "${height}" \
    --argjson lamin "${MAP_LAMIN}" \
    --argjson lamax "${MAP_LAMAX}" \
    --argjson lomin "${MAP_LOMIN}" \
    --argjson lomax "${MAP_LOMAX}" \
    --argjson skip "${skip}" \
    --argjson maxn "${max}" \
    '
    def trim: gsub("^\\s+|\\s+$";"");
    def safe: gsub("[^A-Za-z0-9 ]"; "") | trim;
    ($lamax - $lamin) as $dlat
    | ($lomax - $lomin) as $dlon
    | (($lamin + $lamax) / 2) as $clat
    | (($lomin + $lomax) / 2) as $clon
    | (($clat * 0.017453292519943295) | cos) as $coslat
    | (.states // [])
    | map(select(type == "array" and length > 11))
    | map({
        icao: (.[0] // ""),
        call: ((.[1] // "") | tostring | trim),
        lon: .[5],
        lat: .[6],
        alt: .[7],
        ground: .[9]
      })
    | map(select(
        (.lon | type) == "number"
        and (.lat | type) == "number"
        and .lon >= $lomin and .lon <= $lomax
        and .lat >= $lamin and .lat <= $lamax
        and ($skip == 0 or .ground != true)
      ))
    | map(. + {
        d: (
          ((.lat - $clat) * (.lat - $clat))
          + (((.lon - $clon) * $coslat) * ((.lon - $clon) * $coslat))
        )
      })
    | sort_by(.d)
    | .[0:$maxn]
    | .[]
    | (.alt // 0) as $altm
    | ($altm * 3.28084 | floor) as $ft
    | (if $ft < 10000 then "#7CFF6B"
       elif $ft < 25000 then "#FFE14A"
       else "#7FD4FF" end) as $color
    | ((.lon - $lomin) / $dlon * $w | floor) as $x
    | (($lamax - .lat) / $dlat * $h | floor) as $y
    | ((if .call == "" then .icao else .call end) | safe) as $name
    | "\($x) \($y) \($color) \($name) \($ft)"
    ' "${AIRCRAFT_JSON}" > "${draw_file}"; then
    log_err "jq projection failed; copying bare map"
    cp -f "${MAP_SRC}" "${tmp}" && mv -f "${tmp}" "${FRAME_OUT}"
    exit 0
fi

args=("${MAP_SRC}" -depth 8 -font "${font}" -pointsize 13 -strokewidth 1)
while read -r x y color name ft; do
    [ -n "${x:-}" ] || continue
    [ -n "${name:-}" ] || name="UNKN"
    [ -n "${ft:-}" ] || ft=0
    label="${name} ${ft}"
    args+=(
        -stroke "#000000" -fill "${color}"
        -draw "circle ${x},${y} $((x + 5)),${y}"
        -stroke none -fill "${color}"
        -annotate "+$((x + 8))+$((y - 2))" "${label}"
    )
done < "${draw_file}"

if ! im_convert "${args[@]}" "${tmp}"; then
    log_err "convert failed"
    exit 0
fi

mv -f "${tmp}" "${FRAME_OUT}"
publish_slots "${FRAME_OUT}" || log_err "failed to publish display slots"
trap - EXIT
rm -f "${draw_file}"
exit 0
