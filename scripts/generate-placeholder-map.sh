#!/bin/bash
# Build a dark plate-carrée placeholder that matches MAP_* exactly.
# Replace map.png later with any PNG of the same geographic extent.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

width="${1:-1920}"
height="${2:-1080}"
out="${3:-${MAP_SRC}}"
font="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"

proj() {
    awk -v lat="$1" -v lon="$2" \
        -v lamin="${MAP_LAMIN}" -v lamax="${MAP_LAMAX}" \
        -v lomin="${MAP_LOMIN}" -v lomax="${MAP_LOMAX}" \
        -v w="${width}" -v h="${height}" \
        'BEGIN {
            x = (lon - lomin) / (lomax - lomin) * w
            y = (lamax - lat) / (lamax - lamin) * h
            printf "%d %d\n", x, y
        }'
}

tmp="${out}.partial.png"
args=(
    -size "${width}x${height}" "xc:#0b1220" -depth 8
    -font "${font}"
    -stroke "#1c2a44" -strokewidth 1 -fill none
)

# Lon/lat grid every 0.5°
lat="${MAP_LAMIN}"
while awk -v a="${lat}" -v b="${MAP_LAMAX}" 'BEGIN { exit !(a <= b + 0.001) }'; do
    read -r _ y < <(proj "${lat}" "${MAP_LOMIN}")
    args+=(-draw "line 0,${y} ${width},${y}")
    lat="$(awk -v a="${lat}" 'BEGIN { printf "%.2f", a + 0.5 }')"
done
lon="${MAP_LOMIN}"
while awk -v a="${lon}" -v b="${MAP_LOMAX}" 'BEGIN { exit !(a <= b + 0.001) }'; do
    read -r x _ < <(proj "${MAP_LAMIN}" "${lon}")
    args+=(-draw "line ${x},0 ${x},${height}")
    lon="$(awk -v a="${lon}" 'BEGIN { printf "%.2f", a + 0.5 }')"
done

label_city() {
    local name="$1" lat="$2" lon="$3" x y
    read -r x y < <(proj "${lat}" "${lon}")
    args+=(
        -stroke none -fill "#6b7c99" -pointsize 14
        -draw "circle ${x},${y} $((x + 3)),${y}"
        -annotate "+$((x + 8))+$((y - 2))" "${name}"
    )
}

label_city "Brugge" 51.2094 3.2247
label_city "Gent" 51.0543 3.7174
label_city "Kortrijk" 50.8279 3.2645
label_city "Oostende" 51.2154 2.9286
label_city "Ieper" 50.8510 2.8857
label_city "Roeselare" 50.9465 3.1227
label_city "Lille" 50.6292 3.0573
label_city "Dunkerque" 51.0344 2.3768
label_city "Calais" 50.9513 1.8587
label_city "Dover" 51.1279 1.3134
label_city "Tournai" 50.6051 3.3890
label_city "Brussel" 50.8503 4.3517
label_city "Middelburg" 51.4988 3.6110
label_city "Knokke" 51.3465 3.2875

read -r hx hy < <(proj "${HOME_LAT}" "${HOME_LON}")
args+=(
    -stroke "#FF0000" -strokewidth 3 -fill none
    -draw "line $((hx - 14)),${hy} $((hx + 14)),${hy}"
    -draw "line ${hx},$((hy - 14)) ${hx},$((hy + 14))"
    -stroke none -fill "#FF0000" -pointsize 16
    -annotate "+$((hx + 12))+$((hy + 22))" "home"
    -fill "#8ea0b8" -pointsize 16
    -annotate +24+32 "AirRadio  ${MAP_LAMIN}–${MAP_LAMAX}N  ${MAP_LOMIN}–${MAP_LOMAX}E"
    -pointsize 12
    -annotate +24+$((height - 20)) "Replace map.png with an OSM export of the same lat/lon extent (plate-carree)."
)

if ! im_convert "${args[@]}" "${tmp}"; then
    echo "failed to generate ${out}" >&2
    exit 1
fi
mv -f "${tmp}" "${out}"
echo "wrote ${out} (${width}x${height})"
