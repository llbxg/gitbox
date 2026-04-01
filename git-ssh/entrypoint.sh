#!/usr/bin/env bash
set -euo pipefail

mkdir -p /srv/git
mkdir -p /var/lib/gitbox/ssh

touch /var/lib/gitbox/ssh/authorized_keys

chown -R git:git /srv/git /var/lib/gitbox/ssh
chmod 700 /var/lib/gitbox/ssh
chmod 600 /var/lib/gitbox/ssh/authorized_keys

ln -sfn /srv/git /home/git/repos

exec /usr/sbin/sshd -D -e
