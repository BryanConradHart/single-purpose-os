# Single-Purpose OS

Lightweight, reproducible bootc images that turn a homelab server into one focused service each. Every image is a [uCore](https://github.com/ublue-os/ucore) (Fedora CoreOS) base plus a single purpose, updated through bootc, with no hardware-specific configuration and no workload extras beyond that purpose. All images are published to GHCR.

This repository is the hardware-neutral sibling of [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server), which builds Strix Halo-tuned variants on top of these images.

## Available images

| Variant | Image | Description |
| --- | --- | --- |
| [Arcane Manager](variants/arcane-manager/README.md) | `ghcr.io/bryanconradhart/single-purpose-os-arcane-manager` | [Arcane](https://github.com/getarcaneapp/arcane) for administering local and remote container environments. |
| [Arcane Agent](variants/arcane-agent/README.md) | `ghcr.io/bryanconradhart/single-purpose-os-arcane-agent` | The [Arcane agent](https://github.com/getarcaneapp/arcane) for hosts that connect outbound to Arcane Manager. |

## Install

Choose a variant from the table and copy its image reference.

On a system managed by bootc, replace `IMAGE_FROM_TABLE` with the image from the table, then switch and reboot:

```bash
sudo bootc switch --transport registry IMAGE_FROM_TABLE:latest
sudo systemctl reboot
```

For a clean installation on new hardware, first install [uCore](https://github.com/ublue-os/ucore) by following [uCore's official first-install instructions](https://projectucore.org/docs/first-install/), then run the `bootc switch` above on the installed system.

After installation, visit the variant's README for setup offered after login and application-specific instructions.

## Updates

Routine updates require no reinstallation:

```bash
sudo bootc upgrade
sudo systemctl reboot
```

Application containers with a restart policy of `always` are restarted at boot and updated automatically by Podman's auto-update service. To pin a specific build, switch to its versioned image tag; each variant README shows the command. Images are also rebuilt weekly to pick up upstream security fixes.

All images are signed with cosign; verify with:

```bash
cosign verify --key cosign.pub IMAGE_FROM_TABLE:latest
```
