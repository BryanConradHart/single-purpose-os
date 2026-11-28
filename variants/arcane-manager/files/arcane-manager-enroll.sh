#!/usr/bin/env bash
set -euo pipefail

UNIT=arcane-manager
DROPIN_DIR=/etc/containers/systemd/${UNIT}.container.d
PROJECTS_DROPIN=$DROPIN_DIR/10-projects.conf
DEFAULT_PROJECTS_DIR=/var/home/core/arcane-projects

read_validated_input() {
  local prompt=$1
  local pattern=$2
  local error_message=$3
  local value

  for attempt in 1 2 3; do
    if IFS= read -r -p "$prompt: " value; then
      if [[ "$value" =~ $pattern ]]; then
        printf '%s' "$value"
        return 0
      fi
      echo "$error_message (attempt $attempt of 3)." >&2
    else
      printf '\n' >&2
      echo "No response received (attempt $attempt of 3)." >&2
    fi
  done

  echo "Setup stopped after 3 attempts. Rerun this command to try again." >&2
  return 1
}

# Detection of what the unit already resolves comes from systemd, which performs
# the Quadlet drop-in merge. See /usr/libexec/spos-quadlet-env.sh.
. /usr/libexec/spos-quadlet-env.sh

# --check reports completeness for the login-time notice, which runs as an
# unprivileged user and cannot read the 0600 env file. Exit 0 = incomplete.
# It deliberately skips the daemon-reload below so logging in has no side
# effects; drop-ins added since the last reload are picked up on next boot.
if [[ ${1:-} == --check ]]; then
  if spos_setup_incomplete arcane-manager.service /etc/arcane/manager.env \
      ARCANE_APP_URL; then
    exit 0
  fi
  exit 1
fi

# Reload so drop-ins added since boot are part of the merged unit before it is
# used for the prompts below.
systemctl daemon-reload

url_pattern='^https?://[^[:space:]#\\"]+$'

app_url=
if spos_quadlet_provides arcane-manager.service ARCANE_APP_URL /etc/arcane/manager.env; then
  echo "ARCANE_APP_URL is set by your drop-in override; not asking for it."
  # Keep the previous value (if any) as a fallback in case the override is
  # removed before the next setup run.
  app_url=$(sed -nE 's/^[[:space:]]*ARCANE_APP_URL=//p' /etc/arcane/manager.env 2>/dev/null | tail -n1)
elif ! app_url=$(read_validated_input \
  "Arcane Manager URL (for example https://arcane.example.com)" \
  "$url_pattern" \
  "The Manager URL must start with http:// or https:// and contain no spaces, quotes, backslashes, or fragments"); then
  exit 1
fi

# The merged ExecStart is the final podman command. A mount whose container
# destination is /opt/docker means projects are host-backed, whoever authored
# it. Matches both the -v SRC:DST form (what Volume= emits) and the
# --mount ...,dst=/opt/docker form (what Mount= emits).
if spos_quadlet_exec_matches arcane-manager.service '([^[:space:]]*:/opt/docker([:[:space:]]|$)|(dst|target|destination)=/opt/docker([,:[:space:]]|$))'; then
  echo "Using the projects mount provided by your existing Quadlet drop-in."
elif [[ -f $PROJECTS_DROPIN ]]; then
  echo "Keeping the existing projects drop-in: $PROJECTS_DROPIN"
else
  projects_dir=
  while :; do
    if ! IFS= read -r -p "Host directory for Arcane projects [$DEFAULT_PROJECTS_DIR, or 'none' to skip]: " projects_dir; then
      projects_dir=$DEFAULT_PROJECTS_DIR
    fi
    projects_dir=${projects_dir:-$DEFAULT_PROJECTS_DIR}
    if [[ $projects_dir =~ ^(none|/[^[:space:]]*)$ ]]; then
      break
    fi
    echo "Enter an absolute path starting with /, or 'none'." >&2
  done

  if [[ $projects_dir == none ]]; then
    echo "Skipping the projects mount. Add one later under $DROPIN_DIR."
  else
    install -d -m 0755 "$projects_dir"
    install -d -m 0755 "$DROPIN_DIR"
    printf '# Arcane stores its projects here. Edit this file to change the location.\n# Per https://getarcane.app/docs/podman/setup, the mount and ARCANE_PROJECTS_DIRECTORY must match.\n[Container]\nVolume=%s:/opt/docker\nEnvironment=ARCANE_PROJECTS_DIRECTORY=/opt/docker\n' "$projects_dir" > "$PROJECTS_DROPIN"
    chmod 0644 "$PROJECTS_DROPIN"
    echo "Projects will be stored in $projects_dir (configured in $PROJECTS_DROPIN)."
  fi
fi

install -d -o root -g root -m 0711 /etc/arcane
encryption_key=$(openssl rand -hex 32)
if [[ ! "$encryption_key" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Failed to generate a valid Arcane encryption key."
  exit 1
fi

umask 077
config_tmp=$(mktemp /etc/arcane/manager.env.XXXXXX)
trap 'rm -f "$config_tmp"' EXIT
: > "$config_tmp"
if [[ -n $app_url ]]; then printf 'ARCANE_APP_URL=%s\n' "$app_url" >> "$config_tmp"; fi
printf 'ARCANE_ENCRYPTION_KEY=%s\n' "$encryption_key" >> "$config_tmp"
chown root:root "$config_tmp"
chmod 0600 "$config_tmp"

systemctl start podman.socket
systemctl daemon-reload
mv "$config_tmp" /etc/arcane/manager.env
trap - EXIT

systemctl start arcane-manager.service
echo "Arcane Manager setup completed. Sign in with the initial credentials and change the password."
