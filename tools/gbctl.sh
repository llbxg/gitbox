#!/usr/bin/env bash
set -euo pipefail

GB_DEBUG="${GB_DEBUG:-0}"
POSITIONAL_ARGS=()

die() {
  echo "error: $*" >&2
  exit 1
}

debug() {
  [ "$GB_DEBUG" -eq 1 ] || return 0
  printf '[debug] %s\n' "$*" >&2
}

print_command() {
  [ "$GB_DEBUG" -eq 1 ] || return 0

  printf '[debug] run:' >&2
  for arg in "$@"; do
    printf ' %q' "$arg" >&2
  done
  printf '\n' >&2
}

run_cmd() {
  print_command "$@"
  "$@"
}

parse_global_flags() {
  POSITIONAL_ARGS=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --debug)
        GB_DEBUG=1
        shift
        ;;
      --)
        shift
        POSITIONAL_ARGS+=("$@")
        break
        ;;
      *)
        POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

require_file() {
  local path="$1"
  [ -f "$path" ] || die "file not found: $path"
}

require_engine() {
  local engine="${GB_ENGINE:-}"
  [ -n "$engine" ] || die "GB_ENGINE is required"
}

gb_use_sudo() {
  [ "${GB_USE_SUDO:-0}" = "1" ]
}

run_engine() {
  require_engine

  if gb_use_sudo; then
    run_cmd sudo "$GB_ENGINE" "$@"
  else
    run_cmd "$GB_ENGINE" "$@"
  fi
}

run_container_exec() {
  local container_name="$1"
  shift

  run_engine exec -u root "$container_name" "$@"
}

cleanup_dir() {
  local path="${1:-}"
  [ -n "$path" ] || return 0
  [ -d "$path" ] || return 0
  rm -rf "$path"
}

usage() {
  cat <<EOF
usage:
  $0 [--debug] repoctl <args...>
  $0 [--debug] mirror init <source-url> [dest]
  $0 [--debug] mirror update <name|--all>
  $0 [--debug] mirror cleanup [--dry-run|--apply]
  $0 [--debug] key set <public-key-path>
  $0 [--debug] backup create <archive.tar.gz>
  $0 [--debug] backup apply <archive.tar.gz>

environment:
  GB_ENGINE           container engine command, for example docker or nerdctl
  GB_USE_SUDO         set to 1 to run container engine commands via sudo
  GB_DEBUG            set to 1 to enable debug output
  GB_CONTAINER        git container name (default: git-ssh)
  GB_COMPOSE_PROJECT  compose project name for backup volumes (default: gitbox)
  GB_REPOS_VOLUME     override repos volume name
  GB_SSH_VOLUME       override ssh-data volume name
  GB_HELPER_IMAGE     helper image for backup operations (default: busybox:1.36)
  GB_MIRROR_ROOT      local mirror root
                      default: \${XDG_DATA_HOME:-\$HOME/.local/share}/gitbox/mirrors
EOF
  exit 1
}

normalize_mirror_name() {
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

mirror_root() {
  if [ -n "${GB_MIRROR_ROOT:-}" ]; then
    printf '%s\n' "$GB_MIRROR_ROOT"
    return
  fi

  printf '%s/gitbox/mirrors\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

mirror_repo_path() {
  local name="$1"
  printf '%s/%s.git\n' "$(mirror_root)" "$name"
}

normalize_mirror_dest() {
  local src="$1"
  local dest="${2:-}"
  local base

  if [ -z "$dest" ]; then
    normalize_mirror_name "$src"
    return
  fi

  dest="${dest#repos/}"
  dest="${dest%/}"

  case "$dest" in
    *.git)
      dest="${dest%.git}"
      ;;
    *)
      base="$(normalize_mirror_name "$src")"
      dest="${dest}/$base"
      ;;
  esac

  printf '%s\n' "${dest#/}"
}

mirror_remote_url() {
  local dest="$1"
  printf 'gitbox:repos/%s.git\n' "$dest"
}

git_container_name() {
  printf '%s\n' "${GB_CONTAINER:-git-ssh}"
}

repoctl_cmd() {
  require_engine
  [ $# -gt 0 ] || die "repoctl arguments are required"

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "container: $(git_container_name)"

  run_container_exec "$(git_container_name)" repoctl "$@"
}

mirror_init_cmd() {
  local src="$1"
  local explicit_dest="${2:-}"
  local dest repo root container_name

  require_engine
  dest="$(normalize_mirror_dest "$src" "$explicit_dest")"
  root="$(mirror_root)"
  repo="$(mirror_repo_path "$dest")"
  container_name="$(git_container_name)"

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "mirror root: ${root}"
  debug "container: ${container_name}"

  mkdir -p "$root"

  echo "[mirror] init repos/$dest"

  if [ ! -d "$repo" ]; then
    run_cmd git clone --mirror "$src" "$repo"
  fi

  run_cmd git -C "$repo" remote set-url origin "$src"

  run_container_exec "$container_name" \
    repoctl create "$dest" "Mirror of $src" || true

  if git -C "$repo" remote get-url gitbox >/dev/null 2>&1; then
    run_cmd git -C "$repo" remote set-url gitbox "$(mirror_remote_url "$dest")"
  else
    run_cmd git -C "$repo" remote add gitbox "$(mirror_remote_url "$dest")"
  fi

  run_cmd git -C "$repo" push --mirror gitbox

  echo "[mirror] done repos/$dest"
}

mirror_update_cmd() {
  local name="$1"
  local repo root

  root="$(mirror_root)"
  repo="$(mirror_repo_path "$name")"
  [ -d "$repo" ] || die "not found: $repo"

  debug "mirror root: ${root}"
  echo "[mirror] update repos/$name"

  run_cmd git -C "$repo" remote update
  run_cmd git -C "$repo" push --mirror gitbox

  echo "[mirror] done repos/$name"
}

mirror_list_local_repos() {
  local root="$1"

  [ -d "$root" ] || return 0

  find "$root" -type d -name '*.git' | sort | while IFS= read -r repo_path; do
    mirror_repo_name_from_path "$repo_path"
  done
}

mirror_update_all_cmd() {
  local root updated=0 name

  require_engine
  root="$(mirror_root)"

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "mirror root: ${root}"

  if [ ! -d "$root" ]; then
    echo "[mirror] no local mirror root: $root"
    return 0
  fi

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    updated=1
    mirror_update_cmd "$name"
  done < <(mirror_list_local_repos "$root")

  if [ "$updated" -eq 0 ]; then
    echo "[mirror] no local mirrors"
  fi
}

mirror_repo_name_from_path() {
  local repo_path="$1"
  local root rel

  root="$(mirror_root)"
  rel="${repo_path#$root/}"
  rel="${rel%.git}"
  printf '%s\n' "$rel"
}

repoctl_list_names() {
  local line

  require_engine
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "${line%%$'\t'*}"
  done < <(run_container_exec "$(git_container_name)" repoctl list)
}

mirror_cleanup_cmd() {
  local mode="${1:---dry-run}"
  local root repo_path repo_name removed=0
  local -A remote_repos=()

  require_engine
  root="$(mirror_root)"

  case "$mode" in
    --dry-run|--apply)
      ;;
    *)
      die "unknown mirror cleanup mode: ${mode}"
      ;;
  esac

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "mirror root: ${root}"
  debug "mode: ${mode}"

  if [ ! -d "$root" ]; then
    echo "[mirror] no local mirror root: $root"
    return 0
  fi

  while IFS= read -r repo_name; do
    [ -n "$repo_name" ] || continue
    remote_repos["$repo_name"]=1
  done < <(repoctl_list_names)

  while IFS= read -r repo_name; do

    if [ -n "${remote_repos["repos/$repo_name"]+x}" ]; then
      continue
    fi

    removed=1
    if [ "$mode" = "--apply" ]; then
      echo "[mirror] remove $repo_name"
      run_cmd rm -rf "$repo_path"
    else
      echo "[mirror] stale $repo_name"
    fi
  done < <(mirror_list_local_repos "$root")

  if [ "$removed" -eq 0 ]; then
    echo "[mirror] no stale mirrors"
    return 0
  fi

  if [ "$mode" = "--dry-run" ]; then
    echo "[mirror] dry-run only; rerun with --apply to remove stale mirrors"
  fi
}

key_set_cmd() {
  local path="$1"
  local container_name key_file script

  require_engine
  require_file "$path"
  container_name="$(git_container_name)"
  key_file="/var/lib/gitbox/ssh/authorized_keys"

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "container: ${container_name}"
  debug "key file: ${key_file}"
  debug "public key input: ${path}"

  # shellcheck disable=SC2016
  script='
key_file="$1"
tmp="$(mktemp)"
cat "$key_file" 2>/dev/null > "$tmp" || true
cat >> "$tmp"
sort -u "$tmp" > "${tmp}.new"
cat "${tmp}.new" > "$key_file"
chown git:git "$key_file"
chmod 600 "$key_file"
rm -f "$tmp" "${tmp}.new"
'

  if gb_use_sudo; then
    print_command sudo "$GB_ENGINE" exec -u root -i "$container_name" sh -eu -c "$script" sh "$key_file"
    sudo "$GB_ENGINE" exec -u root -i "$container_name" sh -eu -c "$script" sh "$key_file" < "$path"
  else
    print_command "$GB_ENGINE" exec -u root -i "$container_name" sh -eu -c "$script" sh "$key_file"
    "$GB_ENGINE" exec -u root -i "$container_name" sh -eu -c "$script" sh "$key_file" < "$path"
  fi

  echo "Added key from $path to $container_name:$key_file"
}

volume_exists() {
  run_engine volume inspect "$1" >/dev/null 2>&1
}

compose_project_name() {
  printf '%s\n' "${GB_COMPOSE_PROJECT:-gitbox}"
}

resolve_backup_volume() {
  local logical="$1"
  local override="$2"
  local mode="$3"
  local preferred

  preferred="$(compose_project_name)_${logical}"

  if [ -n "$override" ]; then
    printf '%s\n' "$override"
    return
  fi

  if volume_exists "$preferred"; then
    printf '%s\n' "$preferred"
    return
  fi

  if volume_exists "$logical"; then
    printf '%s\n' "$logical"
    return
  fi

  if [ "$mode" = "apply" ]; then
    printf '%s\n' "$preferred"
    return
  fi

  die "volume not found for ${logical}; tried ${preferred} and ${logical}"
}

helper_image() {
  printf '%s\n' "${GB_HELPER_IMAGE:-busybox:1.36}"
}

backup_save_volume() {
  local volume_name="$1"
  local logical_name="$2"
  local temp_dir="$3"
  local image="$4"

  echo "[backup] saving ${logical_name} from volume ${volume_name}"

  # shellcheck disable=SC2016
  # NOTE: $1 must expand inside the helper shell, not in the outer shell.
  run_engine run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${temp_dir}:/backup" \
    "$image" \
    sh -eu -c 'cd /source && tar -czf "/backup/${1}.tar.gz" .' sh "$logical_name"
}

backup_restore_volume() {
  local volume_name="$1"
  local logical_name="$2"
  local temp_dir="$3"
  local image="$4"

  echo "[backup] restoring ${logical_name} into volume ${volume_name}"

  # shellcheck disable=SC2016
  # NOTE: $1 must expand inside the helper shell, not in the outer shell.
  run_engine run --rm \
    -v "${volume_name}:/target" \
    -v "${temp_dir}:/backup:ro" \
    "$image" \
    sh -eu -c '
      find /target -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
      tar -xzf "/backup/${1}.tar.gz" -C /target
    ' sh "$logical_name"
}

backup_create_cmd() {
  local archive_path="$1"
  local repos_volume ssh_volume image temp_dir project

  require_engine
  repos_volume="$(resolve_backup_volume "repos" "${GB_REPOS_VOLUME:-}" "create")"
  ssh_volume="$(resolve_backup_volume "ssh-data" "${GB_SSH_VOLUME:-}" "create")"
  image="$(helper_image)"
  project="$(compose_project_name)"
  temp_dir="$(mktemp -d)"
  trap "cleanup_dir '$temp_dir'" EXIT

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "compose project: ${project}"
  debug "repos volume: ${repos_volume}"
  debug "ssh volume: ${ssh_volume}"
  debug "helper image: ${image}"

  mkdir -p "$(dirname "$archive_path")"

  backup_save_volume "$repos_volume" "repos" "$temp_dir" "$image"
  backup_save_volume "$ssh_volume" "ssh-data" "$temp_dir" "$image"

  cat > "${temp_dir}/manifest.txt" <<EOF
compose_project=${project}
repos_volume=${repos_volume}
ssh_volume=${ssh_volume}
helper_image=${image}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

  run_cmd tar -C "$temp_dir" -czf "$archive_path" repos.tar.gz ssh-data.tar.gz manifest.txt

  echo "[backup] wrote ${archive_path}"
}

backup_apply_cmd() {
  local archive_path="$1"
  local repos_volume ssh_volume image temp_dir project

  require_engine
  require_file "$archive_path"
  repos_volume="$(resolve_backup_volume "repos" "${GB_REPOS_VOLUME:-}" "apply")"
  ssh_volume="$(resolve_backup_volume "ssh-data" "${GB_SSH_VOLUME:-}" "apply")"
  image="$(helper_image)"
  project="$(compose_project_name)"
  temp_dir="$(mktemp -d)"
  trap "cleanup_dir '$temp_dir'" EXIT

  debug "engine: ${GB_ENGINE}"
  debug "use sudo: ${GB_USE_SUDO:-0}"
  debug "compose project: ${project}"
  debug "repos volume: ${repos_volume}"
  debug "ssh volume: ${ssh_volume}"
  debug "helper image: ${image}"

  run_cmd tar -C "$temp_dir" -xzf "$archive_path"

  [ -f "${temp_dir}/repos.tar.gz" ] || die "archive is missing repos.tar.gz"
  [ -f "${temp_dir}/ssh-data.tar.gz" ] || die "archive is missing ssh-data.tar.gz"

  backup_restore_volume "$repos_volume" "repos" "$temp_dir" "$image"
  backup_restore_volume "$ssh_volume" "ssh-data" "$temp_dir" "$image"

  echo "[backup] applied ${archive_path}"
}

main() {
  local area action

  parse_global_flags "$@"
  set -- "${POSITIONAL_ARGS[@]}"

  area="${1:-}"
  action="${2:-}"

  case "$area" in
    repoctl)
      [ $# -ge 2 ] || usage
      repoctl_cmd "${@:2}"
      ;;
    mirror)
      case "$action" in
        init)
          [ $# -ge 3 ] || usage
          mirror_init_cmd "$3" "${4:-}"
          ;;
        update)
          [ $# -eq 3 ] || usage
          if [ "$3" = "--all" ]; then
            mirror_update_all_cmd
          else
            mirror_update_cmd "$3"
          fi
          ;;
        cleanup)
          [ $# -le 3 ] || usage
          mirror_cleanup_cmd "${3:---dry-run}"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    key)
      case "$action" in
        set)
          [ $# -eq 3 ] || usage
          key_set_cmd "$3"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    backup)
      case "$action" in
        create)
          [ $# -eq 3 ] || usage
          backup_create_cmd "$3"
          ;;
        apply)
          [ $# -eq 3 ] || usage
          backup_apply_cmd "$3"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
