#!/bin/bash
# Long-running framebuffer viewer. Must stay alive: killing fbi blanks vc4 DRM.
set -u
AIRRADIO_ROOT="${AIRRADIO_ROOT:-/opt/airradio}"
# shellcheck disable=SC1091
. "${AIRRADIO_ROOT}/scripts/lib.sh"

if [ ! -f "${FRAME_OUT}" ]; then
    if [ -f "${MAP_SRC}" ]; then
        cp -f "${MAP_SRC}" "${FRAME_OUT}" || true
    fi
fi

if [ -f "${FRAME_OUT}" ]; then
    publish_slots "${FRAME_OUT}" || true
elif [ -f "${MAP_SRC}" ]; then
    publish_slots "${MAP_SRC}" || true
else
    log_err "no map or frame to display"
    exit 1
fi

tty_dev="/dev/tty${FBI_TTY}"
if [ -w "${tty_dev}" ]; then
    setterm --blank 0 --powersave off <"${tty_dev}" >"${tty_dev}" 2>/dev/null || true
fi

# fbi forks and the parent exits. systemd Type=simple then kills the child
# and vc4 DRM blanks. Supervise the surviving fbi so the unit stays active.
fbi_cmd=(fbi -T "${FBI_TTY}" -d "${FB_DEVICE}" -a -noverbose -cachemem 0 -t 8
    "${SLOT_A}" "${SLOT_B}")

cleanup() {
    pkill -f "fbi -T ${FBI_TTY} .*airradio-slot-a" 2>/dev/null || true
}
trap cleanup EXIT TERM INT

"${fbi_cmd[@]}" &
fbi_pid=$!
sleep 1
if ! kill -0 "${fbi_pid}" 2>/dev/null; then
    fbi_pid="$(pgrep -n -f "fbi -T ${FBI_TTY} .*airradio-slot-a" || true)"
fi
if [ -z "${fbi_pid}" ]; then
    log_err "fbi failed to start"
    exit 1
fi

while kill -0 "${fbi_pid}" 2>/dev/null || pgrep -f "fbi -T ${FBI_TTY} .*airradio-slot-a" >/dev/null; do
    sleep 2
done
log_err "fbi exited"
exit 1
