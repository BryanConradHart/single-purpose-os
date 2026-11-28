#!/usr/bin/env bash
set -euo pipefail

read_validated_input() {
  local prompt=$1
  local pattern=$2
  local error_message=$3
  local secret=$4
  local value

  for attempt in 1 2 3; do
    if [[ "$secret" == true ]]; then
      if IFS= read -r -s -p "$prompt: " value; then
        printf '\n' >&2
        if [[ "$value" =~ $pattern ]]; then
          printf '%s' "$value"
          return 0
        fi
        echo "$error_message (attempt $attempt of 3)." >&2
      else
        printf '\n' >&2
        echo "No response received (attempt $attempt of 3)." >&2
      fi
    elif IFS= read -r -p "$prompt: " value; then
      if [[ "$value" =~ $pattern ]]; then
        printf '%s' "$value"
        return 0
      fi
      echo "$error_message (attempt $attempt of 3)." >&2
    else
      echo "No response received (attempt $attempt of 3)." >&2
    fi
  done

  echo "Enrollment stopped after 3 attempts. Rerun this command to try again." >&2
  return 1
}

url_pattern='^https?://[^[:space:]#\\"]+$'

# True when a drop-in for this unit already provides $1, ignoring the setup
# env file (setup regenerates that file; only user-authored drop-ins and the
# env files they reference count). Computed fresh on every run via systemd's
# merged unit view, so removing a drop-in makes the value unset again and the
# next enrollment collects it. See /usr/libexec/spos-quadlet-env.sh.
. /usr/libexec/spos-quadlet-env.sh
override_provides() {
  spos_quadlet_provides arcane-agent.service "$1" /etc/arcane/agent.env
}

# --check reports completeness for the login-time notice, which runs as an
# unprivileged user and cannot read the 0600 env file. Exit 0 = incomplete.
# It deliberately skips the daemon-reload below so logging in has no side
# effects; drop-ins added since the last reload are picked up on next boot.
if [[ ${1:-} == --check ]]; then
  if spos_setup_incomplete arcane-agent.service /etc/arcane/agent.env \
      ARCANE_MANAGER_API_URL ARCANE_AGENT_TOKEN; then
    exit 0
  fi
  exit 1
fi

# Reload so drop-ins added since boot are part of the merged unit before it is
# used for the prompts below.
systemctl daemon-reload

manager_api_url=
if override_provides ARCANE_MANAGER_API_URL; then
  echo "ARCANE_MANAGER_API_URL is set by your drop-in override; not asking for it."
  # Keep the previous value (if any) as a fallback in case the override is
  # removed before the next enrollment.
  manager_api_url=$(sed -nE 's/^[[:space:]]*ARCANE_MANAGER_API_URL=//p' /etc/arcane/agent.env 2>/dev/null | tail -n1)
elif ! manager_api_url=$(read_validated_input \
  "Arcane Manager API URL (for example https://arcane.example.com)" \
  "$url_pattern" \
  "The Manager URL must start with http:// or https:// and contain no spaces, quotes, backslashes, or fragments" \
  false); then
  exit 1
fi

agent_token=
if override_provides ARCANE_AGENT_TOKEN; then
  echo "ARCANE_AGENT_TOKEN is set by your drop-in override; not asking for it."
elif ! agent_token=$(read_validated_input \
  "Arcane Agent token" \
  '^arc_[[:alnum:]_-]+$' \
  "The Arcane token format is invalid" \
  true); then
  exit 1
fi

install -d -o root -g root -m 0711 /etc/arcane

umask 077
config_tmp=$(mktemp /etc/arcane/agent.env.XXXXXX)
trap 'rm -f "$config_tmp"' EXIT
: > "$config_tmp"
if [[ -n $manager_api_url ]]; then printf 'ARCANE_MANAGER_API_URL=%s\n' "$manager_api_url" >> "$config_tmp"; fi
if [[ -n $agent_token ]]; then printf 'ARCANE_AGENT_TOKEN=%s\n' "$agent_token" >> "$config_tmp"; fi
chown root:root "$config_tmp"
chmod 0600 "$config_tmp"

systemctl start podman.socket
systemctl daemon-reload
mv "$config_tmp" /etc/arcane/agent.env
trap - EXIT

systemctl start arcane-agent.service
echo "Arcane Agent enrollment completed."
