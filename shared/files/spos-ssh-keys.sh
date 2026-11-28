#!/usr/bin/env bash
# Authorize the installer SSH key for the core user too, so a key passed to
# `bootc install to-disk --root-ssh-authorized-keys` can log in as core, not just root.
set -euo pipefail

root_keys=/root/.ssh/authorized_keys
[[ -s $root_keys ]] || exit 0

home=$(getent passwd core | cut -d: -f6) || exit 0
[[ -n $home && $home == /* ]] || exit 0

install -d -m 0700 -o core -g core "$home/.ssh"
if [[ ! -s $home/.ssh/authorized_keys ]]; then
  install -m 0600 -o core -g core "$root_keys" "$home/.ssh/authorized_keys"
  restorecon -R "$home/.ssh" 2>/dev/null || true
fi
