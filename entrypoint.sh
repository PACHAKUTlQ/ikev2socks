#!/usr/bin/env bash
set -Eeuo pipefail

CONNECTION="${CONNECTION:?missing CONNECTION}"
TIMEOUT="${TIMEOUT:-120}"
START_DELAY="${START_DELAY:-1}"
SOCKS_PORT="${SOCKS_PORT:-1082}"

ipsec_pid=""
gost_pid=""

cleanup() {
  trap - EXIT INT TERM

  echo "Stopping IPSec connection $CONNECTION..."

  ipsec down "$CONNECTION" >/dev/null 2>&1 || true
  ipsec stop >/dev/null 2>&1 || true

  if [[ -n "$gost_pid" ]] && kill -0 "$gost_pid" 2>/dev/null; then
    kill "$gost_pid" 2>/dev/null || true
    wait "$gost_pid" 2>/dev/null || true
  fi

  if [[ -n "$ipsec_pid" ]] && kill -0 "$ipsec_pid" 2>/dev/null; then
    wait "$ipsec_pid" 2>/dev/null || true
  fi
}

is_established() {
  ipsec status "$CONNECTION" 2>/dev/null | grep -q 'ESTABLISHED'
}

connect_ipsec() {
  local started_at now last_attempt=0

  started_at="$(date +%s)"
  echo "Connecting IPSec connection: $CONNECTION"

  while ! is_established; do
    now="$(date +%s)"

    if ((now - started_at >= TIMEOUT)); then
      echo "IPSec connection timed out after $TIMEOUT seconds."
      ipsec down "$CONNECTION" >/dev/null 2>&1 || true
      return 1
    fi

    if ((last_attempt == 0 || now - last_attempt >= 5)); then
      echo "Running: ipsec up $CONNECTION"
      ipsec up "$CONNECTION" || true
      last_attempt="$now"
    fi

    sleep 1
  done

  echo "IPSec connection $CONNECTION is ESTABLISHED."
}

trap cleanup EXIT
trap 'exit 0' INT TERM

if ! grep -Eq \
  "^[[:space:]]*conn[[:space:]]+([\"\']?$CONNECTION[\"\']?)([[:space:]]*(#.*)?)?$" \
  /etc/ipsec.conf; then
  echo "Connection '$CONNECTION' was not found in /etc/ipsec.conf."
  exit 1
fi

mkdir -p /etc/ipsec.d/cacerts
if [[ -d /etc/ssl/certs ]]; then
  cp -aL /etc/ssl/certs/. /etc/ipsec.d/cacerts/ 2>/dev/null || true
fi

echo "Starting strongSwan..."
ipsec start --nofork &
ipsec_pid="$!"

sleep "$START_DELAY"

if ! kill -0 "$ipsec_pid" 2>/dev/null; then
  echo "strongSwan exited before connection setup."
  exit 1
fi

connect_ipsec

echo "Starting SOCKS5 server on port $SOCKS_PORT..."
gost -L "socks5://:$SOCKS_PORT" &
gost_pid="$!"

while true; do
  if ! kill -0 "$gost_pid" 2>/dev/null; then
    echo "gost exited unexpectedly."
    wait "$gost_pid" || true
    exit 1
  fi

  if ! is_established; then
    echo "IPSec connection was lost; reconnecting..."
    connect_ipsec
  fi

  sleep 10
done
