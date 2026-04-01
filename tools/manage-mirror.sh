#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
MIRROR_ROOT="${MIRROR_ROOT:-$PWD/.mirrors}"
CONTAINER="${GITBOX_CONTAINER:-git-ssh}"

usage() {
  cat <<EOF
usage:
  $0 init <source-url> [name]
  $0 update <name>
EOF
  exit 1
}

normalize_name() {
  local src="$1"
  local name="${2:-}"

  if [ -n "$name" ]; then
    printf '%s\n' "$name"
    return
  fi

  name="$(basename "$src")"
  name="${name%.git}"
  printf '%s\n' "$name"
}

repo_path() {
  local name="$1"
  printf '%s/%s.git\n' "$MIRROR_ROOT" "$name"
}

remote_url() {
  local name="$1"
  printf 'gitbox:repos/mirrors/%s.git\n' "$name"
}

init_cmd() {
  local src="$1"
  local name repo

  name="$(normalize_name "$src" "${2:-}")"
  repo="$(repo_path "$name")"

  mkdir -p "$MIRROR_ROOT"

  echo "[mirror] init mirrors/$name"

  if [ ! -d "$repo" ]; then
    git clone --mirror "$src" "$repo"
  fi

  git -C "$repo" remote set-url origin "$src"

  sudo nerdctl exec -u root "$CONTAINER" \
    repoctl create "mirrors/$name" "Mirror of $src" || true

  if git -C "$repo" remote get-url gitbox >/dev/null 2>&1; then
    git -C "$repo" remote set-url gitbox "$(remote_url "$name")"
  else
    git -C "$repo" remote add gitbox "$(remote_url "$name")"
  fi

  git -C "$repo" push --mirror gitbox

  echo "[mirror] done mirrors/$name"
}

update_cmd() {
  local name="$1"
  local repo

  repo="$(repo_path "$name")"

  [ -d "$repo" ] || {
    echo "not found: $repo" >&2
    exit 1
  }

  echo "[mirror] update mirrors/$name"

  git -C "$repo" remote update
  git -C "$repo" push --mirror gitbox

  echo "[mirror] done mirrors/$name"
}

case "$cmd" in
  init)
    [ $# -ge 2 ] || usage
    init_cmd "$2" "${3:-}"
    ;;
  update)
    [ $# -eq 2 ] || usage
    update_cmd "$2"
    ;;
  *)
    usage
    ;;
esac
