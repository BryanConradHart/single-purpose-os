# Decisions

The reasoning behind choices in [SPEC.md](SPEC.md). When editing the spec, do not violate these decisions; when a spec change conflicts with one, ask the user whether to change the spec or the decision.

Decisions are numbered and grouped by the spec topic they support; keep related decisions adjacent and reference them from the requirements they justify.

Record only non-obvious choices: the alternatives considered, the tradeoffs, and why the rejected options were rejected — the things someone would get wrong or undo without this file. Obvious choices and routine design decisions don't belong here.

## 0001. Machine-specific values and secrets use `EnvironmentFile`, not `Environment=`

### Context

Quadlet `Environment=` keys merge per variable across drop-ins, which makes them look like a convenient place for any value: a drop-in could override a single variable without touching the rest. We still keep secrets and machine-specific values out of image units and drop-ins, in a root-only `EnvironmentFile` instead.

### Decision

Image units bake only non-secret stable defaults as `Environment=`. Setup scripts write machine-specific values (URLs, tokens, API keys, encryption keys) to a `0600` root-only `EnvironmentFile` referenced by the image unit.

### Rationale

- The Quadlet generator translates `Environment=NAME=VALUE` into `--env NAME=VALUE` arguments on the generated service's `ExecStart`. Those values are visible to any local user via `systemctl cat`, `systemctl show -p ExecStart`, `ps`, and `/proc/<pid>/cmdline`. `EnvironmentFile=` puts only the file path on the command line; values stay in the root-only file.
- The env file's existence is the setup-complete signal: units gate on `ConditionPathExists=` and the login offer checks the same file. A file is a clean boolean; drop-ins are user customization territory where existence is ambiguous.
- Ownership separation: setup rewrites the env file wholesale, so it is safe to regenerate; user overrides use the systemd layering mechanism instead. A non-secret override is a single `Environment=` line in a `20-` drop-in, since podman applies `--env` after `--env-file` and inline values therefore win per variable. Only secret overrides need the heavier form — a user-owned env file referenced by the drop-in, where later-`EnvironmentFile` precedence makes it win. The env-file indirection exists solely to keep values out of `ExecStart`, so it is not applied to values with no confidentiality requirement.

## 0002. Live-media `bootc install`, not disk-image provisioning

### Context

Fedora's bootc docs call converting the container to a disk image with bootc-image-builder (ISO/raw/qcow2) the more common way to provision new systems. The uCore base this repository builds on does not support interactive installers; its images are installed with `bootc install to-disk`.

### Decision

Bare-metal installation is documented as booting live media and running `bootc install to-disk` from a container of the image itself. CI publishes container tags only; no installer ISOs or disk images are generated.

### Rationale

- uCore has no interactive installer to boot, so a forked installer ISO would be ours to build and maintain; `bootc install to-disk` is upstream-supported and applies the image's own configuration during install.
- A live Fedora desktop plus one command covers every variant with no per-variant installer artifacts.
- `bootc-image-builder` remains available to users who need machine images (cloud, qcow2); we simply don't publish or maintain those artifacts.

## 0003. Temporary `core` password, SSH key shared to `core` at first boot

### Context

Fedora bootc base images ship no default credentials: root exists with no password, and access is expected via injected SSH keys. Our audience installs homelab servers interactively and needs a console login out of the box. `bootc install --root-ssh-authorized-keys` can only write root's `authorized_keys` (it runs before any user exists).

### Decision

Images provision a `core` user (wheel/sudo) with the temporary password `core` and `chage -d 0`, forcing a password change at first login. A first-boot service copies root's `authorized_keys` to `core` (only when `core` has none), so a headless install key works for `core` as well as root.

### Rationale

- A console password is the simplest usable first login for interactive bare-metal installs; forced rotation means the well-known default is never a standing credential.
- Copying the installer key to `core` keeps headless installs working for the account that owns the home directory and setup flow, without inventing a new key-provisioning mechanism.
