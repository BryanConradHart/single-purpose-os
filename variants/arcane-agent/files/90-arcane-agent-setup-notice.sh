# Setup is offered when a required value is missing. Missing means absent from
# the setup env file and unresolvable from any Quadlet drop-in, so a value the
# user supplies through a drop-in never triggers the offer. The env file is
# root-only, so completeness is checked by the setup script itself. Without
# passwordless sudo, fall back to offering setup whenever the file is absent.
if [ -t 0 ] && [ -t 1 ]; then
  if sudo -n /usr/libexec/arcane-agent-enroll.sh --check 2>/dev/null; then
    incomplete=true
  elif [ ! -e /etc/arcane/agent.env ]; then
    incomplete=true
  else
    incomplete=false
  fi
else
  incomplete=false
fi

if $incomplete; then
  printf '\nArcane Agent enrollment is not complete.\n'
  printf 'Enroll the Agent now? [Y/n] '
  if IFS= read -r answer &&
    case "$answer" in ''|y|Y|yes|YES) true ;; *) false ;; esac; then
    if ! sudo /usr/libexec/arcane-agent-enroll.sh; then
      printf 'Arcane Agent enrollment did not complete. Rerun it with: sudo /usr/libexec/arcane-agent-enroll.sh\n' >&2
    fi
  else
    printf 'Enrollment deferred. It will be offered again at your next login. To run it now: sudo /usr/libexec/arcane-agent-enroll.sh\n'
  fi
fi
