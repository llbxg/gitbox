#!/usr/bin/env bash
set -euo pipefail

require_env() {
    local name="$1"
    : "${!name:?${name} is required}"
}

require_env DEBIAN_DATE
require_env DEBIAN_SUITE

SNAP_TS="${DEBIAN_DATE}T000000Z"

APT_SOURCES_FILE="/etc/apt/sources.list"
SNAP_DEBIAN_URL="http://snapshot.debian.org/archive/debian/${SNAP_TS}"
SNAP_SECURITY_URL="http://snapshot.debian.org/archive/debian-security/${SNAP_TS}"

log() {
    printf '[apt] %s\n' "$*"
}

log "setup snapshot"
log "suite: ${DEBIAN_SUITE}"
log "date:  ${DEBIAN_DATE}"

cat > "${APT_SOURCES_FILE}" <<EOF
deb ${SNAP_DEBIAN_URL} ${DEBIAN_SUITE} main
deb ${SNAP_SECURITY_URL} ${DEBIAN_SUITE}-security main
EOF

apt-get -o Acquire::Check-Valid-Until=false update

log "done"
