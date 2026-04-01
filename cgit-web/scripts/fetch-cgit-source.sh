#!/usr/bin/env bash
set -euo pipefail

require_env() {
    local name="$1"
    : "${!name:?${name} is required}"
}

# ===== Required env =====
require_env CGIT_REPO
require_env CGIT_TAG
require_env CGIT_COMMIT
require_env CGIT_GPG_KEY
require_env CGIT_GPG_FPR
require_env CGIT_KEY_FILE

# ===== Paths =====
BUILD_ROOT="/build"
REPO_DIR="${BUILD_ROOT}/cgit"

OUT_ROOT="/out/usr"
OUT_LIB_DIR="${OUT_ROOT}/lib/cgit"
OUT_DATA_DIR="${OUT_ROOT}/share/cgit"
OUT_FILTER_DIR="${OUT_LIB_DIR}/filters"
OUT_HTML_CONVERTERS_DIR="${OUT_FILTER_DIR}/html-converters"

SRC_FILTER_DIR="filters"
SRC_ABOUT_FILTER="${SRC_FILTER_DIR}/about-formatting.sh"
SRC_HIGHLIGHT_FILTER="${SRC_FILTER_DIR}/syntax-highlighting.py"
SRC_MD2HTML="${SRC_FILTER_DIR}/html-converters/md2html"

# ===== Logging =====
log() {
    printf '[cgit] %s\n' "$*"
}

# ===== Key verification =====
log "import public key"
gpg --batch --import "${CGIT_KEY_FILE}"

actual_fpr="$(
    gpg --batch --with-colons --fingerprint "${CGIT_GPG_KEY}" \
        | awk -F: '/^fpr:/ { print $10; exit }'
)"

if [[ "${actual_fpr}" != "${CGIT_GPG_FPR}" ]]; then
    printf '[cgit] ERROR: fingerprint mismatch\n' >&2
    printf '[cgit] expected: %s\n' "${CGIT_GPG_FPR}" >&2
    printf '[cgit] actual:   %s\n' "${actual_fpr}" >&2
    exit 1
fi

# ===== Fetch source =====
log "clone repo"
git clone "${CGIT_REPO}" "${REPO_DIR}"

cd "${REPO_DIR}"

log "fetch tags"
git fetch --tags --force

log "verify tag"
git verify-tag "${CGIT_TAG}"

actual_commit="$(git rev-list -n 1 "${CGIT_TAG}")"
if [[ "${actual_commit}" != "${CGIT_COMMIT}" ]]; then
    printf '[cgit] ERROR: commit mismatch\n' >&2
    printf '[cgit] expected: %s\n' "${CGIT_COMMIT}" >&2
    printf '[cgit] actual:   %s\n' "${actual_commit}" >&2
    exit 1
fi

log "checkout pinned commit"
git checkout --detach "${CGIT_COMMIT}"

# ===== Build =====
log "build"
make get-git
make NO_LUA=1

log "install"
make install \
    CGIT_SCRIPT_PATH="${OUT_LIB_DIR}" \
    CGIT_DATA_PATH="${OUT_DATA_DIR}"

# ===== Filters =====
log "copy filters"
mkdir -p "${OUT_FILTER_DIR}" "${OUT_HTML_CONVERTERS_DIR}"
cp -a "${SRC_ABOUT_FILTER}" "${OUT_FILTER_DIR}/"
cp -a "${SRC_HIGHLIGHT_FILTER}" "${OUT_FILTER_DIR}/"
cp -a "${SRC_MD2HTML}" "${OUT_HTML_CONVERTERS_DIR}/"

log "done"
