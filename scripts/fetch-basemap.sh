#!/bin/bash
# Bake Google Maps Terrain via the official Static Maps API.
# Coverage is Web Mercator; map.extent.env is written so overlays match.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/config.env"

width="${1:-1920}"
height="${2:-1080}"
out="${3:-${MAP_SRC}}"
font="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
src="${out}.google.png"
tmp="${out}.partial.png"
extent="${AIRRADIO_ROOT}/map.extent.env"

if [ -z "${GOOGLE_MAPS_API_KEY:-}" ]; then
    echo "GOOGLE_MAPS_API_KEY is empty." >&2
    echo "Enable Maps Static API: https://console.cloud.google.com/apis/library/static-maps-backend.googleapis.com" >&2
    echo "Then set GOOGLE_MAPS_API_KEY in ${AIRRADIO_ROOT}/config.env and re-run this script." >&2
    exit 1
fi

# Geographic coverage follows size= (not scale). scale=2 just makes more pixels.
# zoom 8 + 640x360 ≈ the 75 km home box.
req_w=640
req_h=360
zoom="${GOOGLE_MAPS_ZOOM:-8}"
center_lat="${HOME_LAT}"
center_lon="${HOME_LON}"

# Quiet Google's default type: no road shields, muted city names, thin halo.
if ! curl -fsSL --max-time 60 -A "AirRadio/0.6" -o "${src}" --get \
    "https://maps.googleapis.com/maps/api/staticmap" \
    --data-urlencode "center=${center_lat},${center_lon}" \
    --data-urlencode "zoom=${zoom}" \
    --data-urlencode "size=${req_w}x${req_h}" \
    --data-urlencode "scale=2" \
    --data-urlencode "maptype=terrain" \
    --data-urlencode "format=png" \
    --data-urlencode "style=feature:poi|visibility:off" \
    --data-urlencode "style=feature:transit|element:labels|visibility:off" \
    --data-urlencode "style=feature:road|element:labels|visibility:off" \
    --data-urlencode "style=feature:administrative.neighborhood|visibility:off" \
    --data-urlencode "style=element:labels.text.fill|color:0x5a6570" \
    --data-urlencode "style=element:labels.text.stroke|color:0xc8cfd6|weight:1" \
    --data-urlencode "key=${GOOGLE_MAPS_API_KEY}"; then
    echo "Google Static Maps download failed" >&2
    rm -f "${src}"
    exit 1
fi
if ! file "${src}" | grep -q PNG; then
    echo "Google Static Maps did not return a PNG (check the API key / billing):" >&2
    head -c 400 "${src}" >&2 || true
    echo >&2
    rm -f "${src}"
    exit 1
fi

# Actual lat/lon of the image corners (Web Mercator, Google tile math).
# shellcheck disable=SC2086
eval "$(awk -v lat="${center_lat}" -v lon="${center_lon}" -v z="${zoom}" \
    -v w="${req_w}" -v h="${req_h}" 'BEGIN {
    pi = atan2(0, -1)
    world = 256 * (2 ^ z)
    latr = lat * pi / 180
    cx = (lon + 180) / 360 * world
    cy = (1 - log(sin(latr)/cos(latr) + 1/cos(latr)) / pi) / 2 * world
    left = cx - w/2; right = cx + w/2
    top = cy - h/2; bottom = cy + h/2
    lomin = left / world * 360 - 180
    lomax = right / world * 360 - 180
    ntop = pi - 2 * pi * top / world
    nbot = pi - 2 * pi * bottom / world
    # lat = atan(sinh(n)) in degrees
    lamax = atan2(exp(ntop) - exp(-ntop), 2) * 180 / pi
    lamin = atan2(exp(nbot) - exp(-nbot), 2) * 180 / pi
    printf "MAP_LAMIN=%.6f\nMAP_LAMAX=%.6f\nMAP_LOMIN=%.6f\nMAP_LOMAX=%.6f\n", lamin, lamax, lomin, lomax
}')"

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

if ! command -v convert >/dev/null 2>&1 && ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick convert not found" >&2
    exit 1
fi
im() { if command -v convert >/dev/null 2>&1; then convert "$@"; else magick convert "$@"; fi; }

# Gentle dim only — Google terrain is already calm; do not crush colour.
if ! im "${src}" -resize "${width}x${height}!" -depth 8 -modulate 31,90,100 \
    -stroke "#FF0000" -strokewidth 3 -fill none \
    -draw "line $((hx - 16)),${hy} $((hx + 16)),${hy}" \
    -draw "line ${hx},$((hy - 16)) ${hx},$((hy + 16))" \
    -stroke none -fill "#FF0000" -font "${font}" -pointsize 16 \
    -annotate "+$((hx + 12))+$((hy + 22))" "home" \
    "${tmp}"; then
    echo "Google map convert failed" >&2
    rm -f "${src}" "${tmp}"
    exit 1
fi

cat > "${extent}" <<EOF
# Geographic extent of map.png (Google Static Maps, Web Mercator).
MAP_LAMIN=${MAP_LAMIN}
MAP_LAMAX=${MAP_LAMAX}
MAP_LOMIN=${MAP_LOMIN}
MAP_LOMAX=${MAP_LOMAX}
EOF

mv -f "${tmp}" "${out}"
rm -f "${src}"
echo "wrote ${out} (Google terrain z=${zoom})"
echo "extent ${extent}: ${MAP_LAMIN}–${MAP_LAMAX}N ${MAP_LOMIN}–${MAP_LOMAX}E"
