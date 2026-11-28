# Shared helper: "does <unit> already have a value for this variable, once all
# drop-ins are merged?" Used by setup scripts (skip prompts for values the user
# supplied in a drop-in) and login notices (offer setup when something is
# missing). POSIX sh: sourced from /etc/profile.d, not just bash.
#
# Why we parse ExecStart: Quadlet does not put [Container] Environment= /
# EnvironmentFile= into the service's Environment property. It turns them into
# podman arguments on the generated ExecStart:
#
#   Environment=NAME=VAL   ->  --env NAME=VAL
#   EnvironmentFile=PATH   ->  --env-file PATH
#   Volume=SRC:DST         ->  -v SRC:DST
#
# systemd merges drop-ins into that command line, so ExecStart is the single
# authoritative view of the final configuration.

# True when systemd can resolve <unit>. The Quadlet generator only runs during
# daemon-reload, so callers that changed drop-ins must reload first.
spos_quadlet_unit_loaded() {
  [ "$(systemctl show "$1" -p LoadState --value 2>/dev/null)" != not-found ]
}

# True when <unit> provides variable $2, ignoring the setup env file at $3
# (setup rewrites that file, so only user-authored sources count). Looks for
# "--env VAR=" on the merged command line, then for VAR= inside every
# "--env-file" path except the excluded one. Fails closed: if the unit cannot
# be resolved, setup asks for the value rather than silently dropping it.
spos_quadlet_provides() {
  unit=$1
  var=$2
  exclude=$3
  spos_quadlet_unit_loaded "$unit" || return 1
  exec_start=$(systemctl show "$unit" -p ExecStart --value 2>/dev/null) || return 1
  # Inline [Container] Environment=NAME=VAL becomes "--env NAME=VAL".
  printf '%s\n' "$exec_start" |
    grep -Eq -- "(^|[[:space:]])--env[[:space:]]+${var}=" && return 0
  # [Container] EnvironmentFile=PATH becomes "--env-file PATH". Read the paths
  # line-per-path (never word-split: avoids glob expansion on values). Paths
  # containing spaces cannot be parsed reliably and are missed; the failure
  # mode is only a redundant prompt.
  paths=$(printf '%s\n' "$exec_start" |
    grep -oE -- '--env-file[[:space:]]+[^[:space:]]+' |
    sed -E 's/--env-file[[:space:]]+//')
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ "$path" = "$exclude" ] && continue
    [ -f "$path" ] || continue
    grep -Eq "^[[:space:]]*${var}=" "$path" && return 0
  done <<EOF
$paths
EOF
  return 1
}

# True when the merged ExecStart of <unit> matches the extended regex $2. Use
# for settings that are not environment variables, such as the podman mounts
# produced by Quadlet Volume=.
spos_quadlet_exec_matches() {
  spos_quadlet_unit_loaded "$1" || return 1
  systemctl show "$1" -p ExecStart --value 2>/dev/null | grep -Eq -- "$2"
}

# True when the setup env file at $2 is missing, or when at least one required
# variable ($3...) is set nowhere for <unit> once that env file is ignored.
spos_setup_incomplete() {
  unit=$1
  env_file=$2
  shift 2
  [ -e "$env_file" ] || return 0
  for var in "$@"; do
    grep -Eq "^[[:space:]]*${var}=" "$env_file" && continue
    spos_quadlet_provides "$unit" "$var" "$env_file" && continue
    return 0
  done
  return 1
}
