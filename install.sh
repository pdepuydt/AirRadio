#!/bin/bash
# Install AirRadio onto this machine (intended for the Pi Zero W).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${DEST:-/opt/airradio}"

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root: sudo $0" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl jq imagemagick fbi alsa-utils mpv fonts-dejavu-core

mkdir -p "${DEST}/scripts" "${DEST}/data" "${DEST}/systemd"

install -m 0644 "${ROOT}/VERSION" "${DEST}/VERSION"
install -m 0644 "${ROOT}/config.env.example" "${DEST}/config.env.example"
if [ ! -f "${DEST}/config.env" ]; then
    install -m 0644 "${ROOT}/config.env.example" "${DEST}/config.env"
fi

install -m 0755 "${ROOT}/scripts/"*.sh "${DEST}/scripts/"
# lib.sh is sourced; keep it mode 0644
install -m 0644 "${ROOT}/scripts/lib.sh" "${DEST}/scripts/lib.sh"

if [ -f "${ROOT}/map.png" ]; then
    install -m 0644 "${ROOT}/map.png" "${DEST}/map.png"
fi
if [ -f "${ROOT}/README.md" ]; then
    install -m 0644 "${ROOT}/README.md" "${DEST}/README.md"
fi

if [ ! -f "${DEST}/data/aircraft.json" ]; then
    printf '%s\n' '{"time":0,"states":[]}' > "${DEST}/data/aircraft.json"
fi
touch "${DEST}/data/last-error.log"
chmod 0666 "${DEST}/data/last-error.log" "${DEST}/data/aircraft.json"

if [ ! -f "${DEST}/map.png" ]; then
    AIRRADIO_ROOT="${DEST}" "${DEST}/scripts/generate-placeholder-map.sh" 1920 1080 "${DEST}/map.png"
fi

install -m 0644 "${ROOT}/systemd/airradio-radio.service" /etc/systemd/system/airradio-radio.service
install -m 0644 "${ROOT}/systemd/airradio-display.service" /etc/systemd/system/airradio-display.service
install -m 0644 "${ROOT}/systemd/airradio-map.service" /etc/systemd/system/airradio-map.service
install -m 0644 "${ROOT}/systemd/airradio-map.timer" /etc/systemd/system/airradio-map.timer

# Keep the HDMI console from blanking (otherwise the map disappears).
for cmd in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
    if [ -f "${cmd}" ] && ! grep -q 'consoleblank=' "${cmd}"; then
        sed -i 's/$/ consoleblank=0/' "${cmd}"
        echo "added consoleblank=0 to ${cmd}"
    fi
done

# HDMI console is the map; login stays on SSH.
if systemctl is-enabled getty@tty1.service >/dev/null 2>&1; then
    systemctl stop getty@tty1.service || true
    systemctl disable getty@tty1.service || true
    echo "disabled getty@tty1 (HDMI is the map display)"
fi

systemctl daemon-reload
systemctl enable airradio-radio.service airradio-display.service airradio-map.timer
systemctl restart airradio-radio.service
systemctl restart airradio-display.service
systemctl restart airradio-map.timer
# First frame now, do not wait for OnBootSec if this is a live install.
systemctl start airradio-map.service || true

echo "AirRadio installed to ${DEST}"
systemctl --no-pager --full status airradio-radio.service airradio-map.timer || true
