# Single-Purpose OS (Base)

The minimal platform image: uCore plus the single-purpose-os conventions — the `core` login account, rootful Podman with restart-at-boot, and the cosign trust policy for this family's images. There is little reason to run this image directly; it exists as the common starting point that the [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server) variants and your own images build on.

Image: `ghcr.io/bryanconradhart/single-purpose-os-base`

## Install

On a system already managed by bootc, switch to this image and reboot:

```bash
sudo bootc switch --transport registry ghcr.io/bryanconradhart/single-purpose-os-base:latest
sudo systemctl reboot
```

For a clean installation on new hardware, boot a live environment such as the [Fedora Workstation Live image](https://fedoraproject.org), connect to the network, and install the image directly onto the target drive. Identify the drive with `lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS` — the command below erases it, so double-check the device path and do not select the live USB:

```bash
sudo podman run --rm --privileged --pid=host \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev \
  --security-opt label=type:unconfined_t \
  ghcr.io/bryanconradhart/single-purpose-os-base:latest \
  bootc install to-disk --wipe --generic-image /dev/REPLACE_WITH_TARGET_DISK
```

Reboot, then sign in as `core` with the temporary password `core` and choose a new password. For a headless install, mount your public key into the container with `-v "$HOME/.ssh/id_ed25519.pub:/tmp/key.pub:ro"` and add `--root-ssh-authorized-keys /tmp/key.pub` to the install command; the key authorizes root, and first boot also installs it for `core`. See the root [installation instructions](../../README.md) for the full details.

The base image has no interactive first-boot script or additional setup.

## Running your own containers

The base image ships no workload services. Deploy long-running containers as rootful Podman Quadlet files in `/etc/containers/systemd/`, which survives `bootc upgrade` and `bootc switch`. Quadlet services start at boot, are managed with `systemctl`, are restarted at boot by `podman-restart.service` (enabled in this image), and update themselves via `podman-auto-update.timer` (also enabled) when you set `AutoUpdate=registry`. A minimal service looks like this:

```ini
# /etc/containers/systemd/hello.container
[Container]
Image=docker.io/library/nginx:alpine
PublishPort=8080:80
AutoUpdate=registry

[Install]
WantedBy=multi-user.target
```

Then generate and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl start hello.service
```

To have your own Quadlet present from the first boot instead of adding it after login, write the file with any editor, then place it on the target system while installing with `bootc install to-disk`: after the installer finishes and before you reboot, mount the installed system's root partition (check with `lsblk`; for example `/dev/nvme0n1p3`) and copy the file into its `/etc`:

```bash
sudo mkdir -p /mnt/newroot
sudo mount /dev/REPLACE_WITH_ROOT_PARTITION /mnt/newroot
sudo install -D -m 0644 hello.container \
  /mnt/newroot/sysroot/ostree/deploy/*/deploy/*.0/etc/containers/systemd/hello.container
sudo umount /mnt/newroot
```

The [installation instructions](../../README.md) cover the same technique for drop-ins, which modify services that an image already ships.

## Building your own image

Point a [BlueBuild](https://blue-build.org/) recipe at this image to get a blank slate with the platform conventions already in place — see [Customizing by extending an image](../../README.md#customizing-by-extending-an-image-advanced) in the root README.

## Updates

After installation, upgrades are handled through bootc. Check the current image state and upgrade to the newest build:

```bash
sudo bootc status
sudo bootc upgrade
sudo systemctl reboot
```

To switch directly to a specific image tag:

```bash
sudo bootc switch --transport registry ghcr.io/bryanconradhart/single-purpose-os-base:vYYYY.MM.DD-HHMMSS-rRUN_NUMBER
sudo systemctl reboot
```

Each build publishes a `latest` tag and a versioned tag in the form `vYYYY.MM.DD-HHMMSS-rRUN_NUMBER`. See the [published image page](https://github.com/BryanConradHart/single-purpose-os/pkgs/container/single-purpose-os-base) for available tags.
