#!/usr/bin/env bash
# Set ftdi_sio latency_timer for a single FTDI UART used by the INS (reduces USB bulk batching).
#
# Default: /dev/serial/by-id/usb-FTDI_FT231X_USB_UART_D30ECJSY-if00-port0  (0403:6015)
# Override:
#   DEVICE_BY_ID="usb-FTDI_FT231X_USB_UART_<YOUR_SERIAL>-if00-port0" ./set_ftdi_ins_usb_latency.sh
#   LATENCY_MS=1 ./set_ftdi_ins_usb_latency.sh

set -euo pipefail

readonly WANT_VENDOR_ID="0403"
readonly WANT_PRODUCT_ID="6015"
readonly DEFAULT_BY_ID="usb-FTDI_FT231X_USB_UART_D30ECJSY-if00-port0"

DEVICE_BY_ID="${DEVICE_BY_ID:-$DEFAULT_BY_ID}"
LATENCY_MS="${LATENCY_MS:-1}"

if [[ ! "$LATENCY_MS" =~ ^[0-9]+$ ]] || ((LATENCY_MS < 1 || LATENCY_MS > 255)); then
  echo "error: LATENCY_MS must be an integer 1-255 (got ${LATENCY_MS})" >&2
  exit 1
fi

by_id_path="/dev/serial/by-id/${DEVICE_BY_ID}"

if [[ ! -e "$by_id_path" ]]; then
  echo "error: device symlink not found: $by_id_path" >&2
  echo "  Plug in the INS adapter and check: ls -l /dev/serial/by-id/usb-FTDI_*" >&2
  exit 1
fi

tty_path="$(readlink -f "$by_id_path")"
if [[ ! -c "$tty_path" ]]; then
  echo "error: resolved path is not a character device: $tty_path" >&2
  exit 1
fi

vid="$(udevadm info -q property -n "$tty_path" 2>/dev/null | sed -n 's/^ID_VENDOR_ID=//p' || true)"
pid="$(udevadm info -q property -n "$tty_path" 2>/dev/null | sed -n 's/^ID_MODEL_ID=//p' || true)"

if [[ "$vid" != "$WANT_VENDOR_ID" || "$pid" != "$WANT_PRODUCT_ID" ]]; then
  echo "error: $tty_path is not the expected FTDI adapter (${WANT_VENDOR_ID}:${WANT_PRODUCT_ID})." >&2
  echo "  udev reports ID_VENDOR_ID=${vid:-?} ID_MODEL_ID=${pid:-?}" >&2
  exit 1
fi

port_name="$(basename "$tty_path")"
latency_file="/sys/bus/usb-serial/devices/${port_name}/latency_timer"

if [[ ! -f "$latency_file" ]]; then
  echo "error: latency_timer sysfs node missing: $latency_file" >&2
  echo "  Is this port using the usb-serial (ftdi_sio) driver?" >&2
  exit 1
fi

old="$(cat "$latency_file")"
write_latency() {
  local target="$1"
  if [[ -w "$latency_file" ]]; then
    echo "$target" >"$latency_file"
  else
    sudo sh -c "echo '$target' >'$latency_file'"
  fi
}

write_latency "$LATENCY_MS"
new="$(cat "$latency_file")"

echo "Device:    $by_id_path -> $tty_path"
echo "USB ID:    ${vid}:${pid}"
echo "latency_timer: ${old} ms -> ${new} ms (requested ${LATENCY_MS} ms)"
