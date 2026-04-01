#!/usr/bin/env bash
set -euo pipefail

engine="${1:?engine is required}"
sudo_prefix="${2:-}"
path="${3:?public key file path is required}"

container_name="${CONTAINER_NAME:-git-ssh}"
key_file="/var/lib/gitbox/ssh/authorized_keys"

run() {
    if [ -n "$sudo_prefix" ]; then
        sudo "$@"
    else
        "$@"
    fi
}

[ -f "$path" ] || {
    echo "error: file not found: $path" >&2
    exit 1
}

# shellcheck disable=SC2016
# NOTE: use single quotes so variables ($1, etc.) are expanded in the inner shell,
# not by the outer shell.
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

run "$engine" exec -u root -i "$container_name" sh -eu -c "$script" sh "$key_file" < "$path"

echo "Added key from $path to $container_name:$key_file"
