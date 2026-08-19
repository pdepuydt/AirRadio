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

if [ ! -f "${ROUTES_JSON}" ]; then
    echo '{}' > "${ROUTES_JSON}"
    chmod 644 "${ROUTES_JSON}"
fi

if ! jq -r \
    --argjson w "${width}" \
    --argjson h "${height}" \
    --argjson lamin "${MAP_LAMIN}" \
    --argjson lamax "${MAP_LAMAX}" \
    --argjson lomin "${MAP_LOMIN}" \
    --argjson lomax "${MAP_LOMAX}" \
    --argjson skip "${skip}" \
    --argjson maxn "${max}" \
    --slurpfile routes "${ROUTES_JSON}" \
    '
    def trim: gsub("^\\s+|\\s+$";"");
    def safe: gsub("[^A-Za-z0-9 -]"; "") | gsub(" +"; " ") | trim;
    # Web Mercator Y — Google Static Maps / terrain tiles.
    def merc_y:
      ((. * 0.017453292519943295 / 2) + 0.7853981633974483) as $a
      | (($a | sin) / ($a | cos)) | log;
    ($routes[0] // {}) as $rt
    | ($lamax | merc_y) as $my0
    | ($lamin | merc_y) as $my1
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
        ground: .[8],
        vrate: .[11]
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
    | "#FFEE00" as $color
    | ((.lon - $lomin) / $dlon * $w | floor) as $x
    | (($my0 - (.lat | merc_y)) / ($my0 - $my1) * $h | floor) as $y
    | ((.call | trim) as $cs
       | (if (($rt[$cs].ok // false) == true) and (($rt[$cs].route // "") != "")
          then $rt[$cs].route
          elif $cs == "" then .icao
          else $cs end
         ) | safe) as $name
    | (if (.vrate | type) != "number" then "cr"
       elif .vrate > 1 then "up"
       elif .vrate < -1 then "dn"
       else "cr" end) as $trend
    | "\($x)\t\($y)\t\($color)\t\($trend)\t\($name)\t\($ft)"
    ' "${AIRCRAFT_JSON}" > "${draw_file}"; then
    log_err "jq projection failed; copying bare map"
    cp -f "${MAP_SRC}" "${tmp}" && mv -f "${tmp}" "${FRAME_OUT}"
    exit 0
fi

# Vertical-rate mark in the label (DejaVu). Deadband ±1 m/s ≈ 200 ft/min.
export LANG="${LANG:-C.UTF-8}"
args=("${MAP_SRC}" -depth 8 -font "${font}" -pointsize 21 -strokewidth 1)
while IFS=$'\t' read -r x y color trend name ft; do
    [ -n "${x:-}" ] || continue
    [ -n "${name:-}" ] || name="UNKN"
    [ -n "${ft:-}" ] || ft=0
    case "${trend}" in
        up) mark="▲" ;;
        dn) mark="▼" ;;
        *)  mark="–" ;;
    esac
    label="${name} ${mark}${ft}"
    args+=(
        -stroke "#000000" -fill "${color}"
        -draw "circle ${x},${y} $((x + 4)),${y}"
        -stroke none -fill "${color}"
        -annotate "+$((x + 8))+$((y - 2))" "${label}"
    )
done < "${draw_file}"

hx="$(awk -v lon="${HOME_LON}" -v lomin="${MAP_LOMIN}" -v lomax="${MAP_LOMAX}" -v w="${width}" \
    'BEGIN { printf "%d", (lon - lomin) / (lomax - lomin) * w }')"
hy="$(awk -v lat="${HOME_LAT}" -v lamin="${MAP_LAMIN}" -v lamax="${MAP_LAMAX}" -v h="${height}" 'BEGIN {
    pi = atan2(0, -1)
    latr = lat * pi / 180
    rmax = lamax * pi / 180
    rmin = lamin * pi / 180
    mylat = log(sin(latr)/cos(latr) + 1/cos(latr))
    mymax = log(sin(rmax)/cos(rmax) + 1/cos(rmax))
    mymin = log(sin(rmin)/cos(rmin) + 1/cos(rmin))
    printf "%d", (mymax - mylat) / (mymax - mymin) * h
}')"
args+=(
    -stroke "#FF0000" -strokewidth 3 -fill none
    -draw "line $((hx - 16)),${hy} $((hx + 16)),${hy}"
    -draw "line ${hx},$((hy - 16)) ${hx},$((hy + 16))"
    -stroke none -fill "#FF0000" -pointsize 16
    -annotate "+$((hx + 14))+$((hy + 24))" "home"
)

if ! im_convert "${args[@]}" "${tmp}"; then
    log_err "convert failed"
    exit 0
fi

mv -f "${tmp}" "${FRAME_OUT}"
trap - EXIT
rm -f "${draw_file}"
exit 0
