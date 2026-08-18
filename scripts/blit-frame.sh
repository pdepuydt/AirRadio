#!/bin/bash
# Decode FRAME_OUT and write one full RGB565 frame to the HDMI framebuffer.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

pack="${AIRRADIO_ROOT}/scripts/rgb24-to-fb16"
src="${1:-${FRAME_OUT}}"
fb="${2:-${FB_DEVICE}}"
rgb24="${RGB24_TMP:-/tmp/airradio-rgb24.raw}"

if [ ! -x "${pack}" ]; then
    log_err "missing ${pack} (compile rgb24-to-fb16.c)"
    exit 1
fi
if [ ! -f "${src}" ]; then
    log_err "no frame to blit: ${src}"
    exit 1
fi
if [ ! -e "${fb}" ]; then
    log_err "framebuffer missing: ${fb}"
    exit 1
fi

fb_sys="/sys/class/graphics/$(basename "${fb}")"
width="$(cut -d, -f1 "${fb_sys}/virtual_size")"
height="$(cut -d, -f2 "${fb_sys}/virtual_size")"
stride="$(cat "${fb_sys}/stride")"
bpp="$(cat "${fb_sys}/bits_per_pixel")"
if [ "${bpp}" != "16" ]; then
    log_err "expected 16-bit fb, got ${bpp}"
    exit 1
fi

if ! im_convert "${src}" -depth 8 -resize "${width}x${height}!" "rgb:${rgb24}"; then
    log_err "convert to RGB24 failed"
    exit 1
fi

if ! "${pack}" "${rgb24}" "${fb}" "${width}" "${height}" "${stride}"; then
    log_err "rgb24-to-fb16 failed"
    exit 1
fi
exit 0
