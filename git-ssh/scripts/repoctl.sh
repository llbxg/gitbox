#!/usr/bin/env bash
set -euo pipefail

ROOT="/srv/git"
OWNER="git:git"

usage() {
  cat <<'EOF'
usage:
  repoctl create <name> [description]
  repoctl set-desc <name> <description>
  repoctl get-desc <name>
  repoctl list
  repoctl rename <old-name> <new-name>
  repoctl delete <name>
EOF
}

normalize_repo_name() {
  local name="$1"
  case "$name" in
    *.git) printf '%s\n' "$name" ;;
    *) printf '%s.git\n' "$name" ;;
  esac
}

repo_path() {
  local repo
  repo="$(normalize_repo_name "$1")"
  printf '%s/%s\n' "$ROOT" "$repo"
}

repo_display_name() {
  local path="$1"
  local rel

  rel="${path#$ROOT/}"
  rel="${rel%.git}"
  printf 'repos/%s\n' "$rel"
}

require_repo_exists() {
  local path="$1"
  if [ ! -d "$path" ]; then
    echo "repository not found: $path" >&2
    exit 1
  fi
}

require_repo_not_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    echo "repository already exists: $path" >&2
    exit 1
  fi
}

cmd_create() {
  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
    exit 1
  fi

  local repo path desc
  repo="$(normalize_repo_name "$1")"
  path="$ROOT/$repo"
  desc="${2:-Unnamed repository}"

  require_repo_not_exists "$path"

  mkdir -p "$(dirname "$path")"

  git init --bare --initial-branch=main "$path" >/dev/null
  printf '%s\n' "$desc" > "$path/description"
  chown -R "$OWNER" "$path"

  echo "created: $path"
}

cmd_set_desc() {
  if [ $# -ne 2 ]; then
    usage
    exit 1
  fi

  local path
  path="$(repo_path "$1")"
  require_repo_exists "$path"

  printf '%s\n' "$2" > "$path/description"
  chown "$OWNER" "$path/description"

  echo "updated description: $path"
}

cmd_get_desc() {
  if [ $# -ne 1 ]; then
    usage
    exit 1
  fi

  local path
  path="$(repo_path "$1")"
  require_repo_exists "$path"

  if [ -f "$path/description" ]; then
    cat "$path/description"
  fi
}

cmd_list() {
  local dir

  find "$ROOT" -type d -name '*.git' | sort | while IFS= read -r dir; do
    [ -d "$dir" ] || continue

    printf '%s' "$(repo_display_name "$dir")"
    if [ -f "$dir/description" ]; then
      printf '\t%s' "$(tr '\n' ' ' < "$dir/description" | sed 's/[[:space:]]*$//')"
    fi
    printf '\n'
  done
}

cmd_rename() {
  if [ $# -ne 2 ]; then
    usage
    exit 1
  fi

  local old_path new_repo new_path
  old_path="$(repo_path "$1")"
  new_repo="$(normalize_repo_name "$2")"
  new_path="$ROOT/$new_repo"

  require_repo_exists "$old_path"
  require_repo_not_exists "$new_path"

  mkdir -p "$(dirname "$new_path")"

  mv "$old_path" "$new_path"
  chown -R "$OWNER" "$new_path"

  echo "renamed: $old_path -> $new_path"
}

cmd_delete() {
  if [ $# -ne 1 ]; then
    usage
    exit 1
  fi

  local path
  path="$(repo_path "$1")"
  require_repo_exists "$path"

  rm -rf "$path"
  echo "deleted: $path"
}

main() {
  if [ $# -lt 1 ]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    create)   cmd_create "$@" ;;
    set-desc) cmd_set_desc "$@" ;;
    get-desc) cmd_get_desc "$@" ;;
    list)     cmd_list "$@" ;;
    rename)   cmd_rename "$@" ;;
    delete)   cmd_delete "$@" ;;
    -h|--help|help) usage ;;
    *)
      echo "unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
