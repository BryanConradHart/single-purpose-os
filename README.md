# Single-Purpose OS

Lightweight, reproducible bootc images that turn a homelab server into one focused service each. Every image is a [uCore](https://github.com/ublue-os/ucore) (Fedora CoreOS) base plus a single purpose, updated through bootc, with no hardware-specific configuration and no workload extras beyond that purpose. All images are published to GHCR.

This repository is the hardware-neutral sibling of [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server), which builds Strix Halo-tuned variants on top of these images.

## Available images

| Variant | Image | Description |
| --- | --- | --- |
| [Base](variants/base/README.md) | `ghcr.io/bryanconradhart/single-purpose-os-base` | Minimal platform image. A starting point for downstream images such as strix-halo-server, not a workload. |
| [Arcane Manager](variants/arcane-manager/README.md) | `ghcr.io/bryanconradhart/single-purpose-os-arcane-manager` | [Arcane](https://github.com/getarcaneapp/arcane) for administering local and remote container environments. |
| [Arcane Agent](variants/arcane-agent/README.md) | `ghcr.io/bryanconradhart/single-purpose-os-arcane-agent` | The [Arcane agent](https://github.com/getarcaneapp/arcane) for hosts that connect outbound to Arcane Manager. |

## Install

Choose a variant from the table and copy its image reference.

On a system managed by bootc, replace `IMAGE_FROM_TABLE` with the image from the table, then switch and reboot:

```bash
sudo bootc switch --transport registry IMAGE_FROM_TABLE:latest
sudo systemctl reboot
```

For a clean installation on new hardware, boot a live environment such as the [Fedora Workstation Live image](https://fedoraproject.org), connect to the network, and install the image directly onto the target drive. Identify the drive with `lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS` — the command below erases it, so double-check the device path and do not select the live USB:

```bash
sudo podman run --rm --privileged --pid=host \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev \
  --security-opt label=type:unconfined_t \
  IMAGE_FROM_TABLE:latest \
  bootc install to-disk --wipe --generic-image /dev/REPLACE_WITH_TARGET_DISK
```

Reboot, then sign in as `core` with the temporary password `core` and choose a new password. For a headless install, add `--root-ssh-authorized-keys /tmp/key.pub` to the install command and mount your public key into the container with `-v "$HOME/.ssh/id_ed25519.pub:/tmp/key.pub:ro"`. The key authorizes root, and first boot also installs it for `core`, so you can sign in as either. If you don't have a key pair yet, create one first with `ssh-keygen -t ed25519` and use the generated `.pub` file.

After installation, visit the variant's README for setup offered after login and application-specific instructions.

### Customizing by extending an image (advanced)

Customizations that suit an image — packages, files, units, services — are best baked in by building your own [BlueBuild](https://blue-build.org/) image on top of one of ours. Baked configuration travels with the image: a new install arrives already configured. For advanced users; [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server) is a working example of extending [single-purpose-os-base](variants/base/README.md) and the variant images, and the [BlueBuild setup guide](https://blue-build.org/how-to/setup/) covers the CI side.

A minimal recipe (`recipes/home-lab.yml`):

```yaml
name: home-lab
base-image: ghcr.io/bryanconradhart/single-purpose-os-arcane-manager
image-version: latest
modules:
  - type: dnf
    install:
      packages:
        - htop
```

Publish to your own registry, then point the host at your image once, and follow the existing installation instructions for the variant you extended:

```bash
sudo bootc switch --transport registry ghcr.io/YOUR_GITHUB_USER/home-lab:latest
sudo systemctl reboot
```

Your image inherits our services and setup scripts and picks up our changes whenever you rebuild on a newer `image-version`.

### Customizing services with Quadlet drop-ins

Drop-ins add host customization on top of a baked image — ours or one you built — without rebuilding it. Use them for settings that shouldn't be baked into the image, such as machine-specific values in an image shared across hosts, or secrets. A drop-in is a small configuration file merged into the service definition at boot, so mounts, ports, and environment values can vary per host. Drop-ins live in `/etc/containers/systemd/<service>.container.d/` and survive updates.

Create a drop-in with any editor, for example `20-extra-mount.conf`:

```ini
[Container]
Volume=/srv/shared-data:/srv/shared-data:ro
```

To have it active from the first boot, place it on the target system while installing with `bootc install to-disk`: after the installer finishes and before you reboot, mount the installed system's root partition (check with `lsblk`; for example `/dev/nvme0n1p3`) and copy the file into the deployment's `/etc`:

```bash
sudo mkdir -p /mnt/newroot
sudo mount /dev/REPLACE_WITH_ROOT_PARTITION /mnt/newroot
sudo install -D -m 0644 20-extra-mount.conf \
  /mnt/newroot/sysroot/ostree/deploy/*/deploy/*.0/etc/containers/systemd/<service>.container.d/20-extra-mount.conf
sudo umount /mnt/newroot
```

Drop-ins can also be added to a running system. Name your drop-ins `20-` or higher so they sort after the ones setup creates: setup regenerates its own files, and yours are never touched.

Gotchas:

- Drop-ins are applied in lexicographic (alphabetical) filename order — `aaa` comes before `aab`, `10-` comes before `20-`.
- Single-value settings (`Image=`, `Memory=`): the last assignment wins.
- List settings (`Volume=`, `PublishPort=`): assignments accumulate and entries never collide. Assigning an empty value (`Volume=`) resets the list, so restate anything you want to keep after it.
- Keyed list settings (`Environment=`): assignments accumulate, and re-assigning the same key (`FOO=`) overrides its earlier value. Assigning an empty value (`Environment=`) resets the list.
- `EnvironmentFile=` is a list setting: each entry adds a file. The files are expanded into the same keyed list when the container starts, in the order listed, so a key in a later file overrides the same key from an earlier file.
- Inline `Environment=` entries are applied after all env files, so they override any file value.
- Don't put credentials in inline `Environment=` values; keep them in a file referenced by `EnvironmentFile=`. Inline values can be read back with `systemctl show` or from the process list.
- Write an env file before the drop-in that references it — the service won't start if the file is missing.
- Bring a setting into your own drop-in only when you intend to change it. Re-declaring the shipped unit or a setup-created drop-in just to edit one line freezes the rest of that layer against future updates.

The variant READMEs list drop-in examples for each service.

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
