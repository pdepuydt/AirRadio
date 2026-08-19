#!/bin/bash
# Paint top clock/date and/or bottom radio ticker onto the HDMI framebuffer.
# Bars flush to the top and bottom of /dev/fb0 (HUD_MARGIN_Y=0).
# Usage: hud-bars.sh [all|top|bot]
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

which="${1:-all}"
pack="${AIRRADIO_ROOT}/scripts/rgb24-to-fb16"
font="${FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
fb="${FB_DEVICE:-/dev/fb0}"
bar_h="${HUD_BAR_H:-64}"
top_h="${HUD_TOP_H:-100}"
margin_y="${HUD_MARGIN_Y:-0}"
pad_x="${HUD_PAD_X:-40}"
now_file="${NOWPLAYING_FILE:-/tmp/airradio-nowplaying.txt}"
station="${RADIO_NAME:-Nostalgie Vlaanderen}"

export LANG="${LANG:-C.UTF-8}"
export TZ="${TZ:-Europe/Brussels}"

if [ ! -x "${pack}" ] || [ ! -e "${fb}" ]; then
    exit 1
fi

fb_sys="/sys/class/graphics/$(basename "${fb}")"
width="$(cut -d, -f1 "${fb_sys}/virtual_size")"
height="$(cut -d, -f2 "${fb_sys}/virtual_size")"
stride="$(cat "${fb_sys}/stride")"
bpp="$(cat "${fb_sys}/bits_per_pixel")"
if [ "${bpp}" != "16" ]; then
    exit 1
fi

im_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/%/%%/g; s/"/\\"/g'
}

# Same bar colour behind glyphs so AA has no black fringe.
bar_bg="#10151c"

paint_top() {
    local clock dateline top_rgb clock_png date_png
    local clock_w clock_h date_w date_h clock_y date_y date_x top_y
    clock="$(date '+%H:%M')"
    dateline="$(date '+%A  %-d %B %Y')"
    top_rgb="/tmp/airradio-hud-top.rgb"
    clock_png="/tmp/airradio-hud-clock.png"
    date_png="/tmp/airradio-hud-date.png"

    if ! im_convert -depth 8 -background "${bar_bg}" -font "${font}" -fill "#e8eef4" \
        -pointsize 52 "label:$(im_escape "${clock}")" +repage "${clock_png}"; then
        return 1
    fi
    if ! im_convert -depth 8 -background "${bar_bg}" -font "${font}" -fill "#e8eef4" \
        -pointsize 36 "label:$(im_escape "${dateline}")" +repage "${date_png}"; then
        return 1
    fi
    clock_w="$(im_identify -format "%w" "${clock_png}")"
    clock_h="$(im_identify -format "%h" "${clock_png}")"
    date_w="$(im_identify -format "%w" "${date_png}")"
    date_h="$(im_identify -format "%h" "${date_png}")"
    clock_y=$(( (top_h - clock_h) / 2 ))
    date_y=$(( (top_h - date_h) / 2 ))
    date_x=$((width - pad_x - date_w))
    [ "${date_x}" -lt 0 ] && date_x=0
    [ "${clock_y}" -lt 0 ] && clock_y=0
    [ "${date_y}" -lt 0 ] && date_y=0

    if ! im_convert -depth 8 -size "${width}x${top_h}" "xc:${bar_bg}" \
        "${clock_png}" -geometry "+${pad_x}+${clock_y}" -composite \
        "${date_png}" -geometry "+${date_x}+${date_y}" -composite \
        "rgb:${top_rgb}"; then
        return 1
    fi
    top_y="${margin_y}"
    "${pack}" "${top_rgb}" "${fb}" "${width}" "${top_h}" "${stride}" "${top_y}"
}

paint_bot() {
    local track line bot_rgb tick_png tick_h tick_y bot_y
    track=""
    if [ -f "${now_file}" ]; then
        track="$(tr -d '\r\n' < "${now_file}")"
    fi
    if [ -n "${track}" ]; then
        line="${station}     ·     ${track}          "
    else
        line="${station}          "
    fi

    bot_rgb="/tmp/airradio-hud-bot.rgb"
    tick_png="/tmp/airradio-hud-tick.png"
    if ! im_convert -depth 8 -background "${bar_bg}" -font "${font}" -fill "#d7dee6" \
        -pointsize 20 "label:$(im_escape "${line}")" +repage "${tick_png}"; then
        return 1
    fi
    tick_h="$(im_identify -format "%h" "${tick_png}")"
    tick_y=$(( (bar_h - tick_h) / 2 ))
    [ "${tick_y}" -lt 0 ] && tick_y=0

    # Static left-aligned ticker. Long titles clip at the bar edge.
    if ! im_convert -depth 8 -size "${width}x${bar_h}" "xc:${bar_bg}" \
        "${tick_png}" -geometry "+${pad_x}+${tick_y}" -composite \
        "rgb:${bot_rgb}"; then
        return 1
    fi
    bot_y=$((height - margin_y - bar_h))
    "${pack}" "${bot_rgb}" "${fb}" "${width}" "${bar_h}" "${stride}" "${bot_y}"
}

case "${which}" in
    top)
        paint_top
        ;;
    bot)
        paint_bot
        ;;
    all|"")
        paint_top || exit 1
        paint_bot
        ;;
    *)
        echo "usage: hud-bars.sh [all|top|bot]" >&2
        exit 2
        ;;
esac
