# Specification

This repository defines single-purpose bootable container images for homelab servers. Each published image is a small, focused, self-contained system: a uCore (Fedora CoreOS) base plus one purpose, updated through bootc. The root [README.md](README.md) catalogs the images and links to image-specific installation and administration instructions. The *why* behind these requirements lives in [DECISIONS.md](DECISIONS.md).

This repository is the hardware-neutral sibling of [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server). Keep it free of hardware-specific kernel arguments and free of AI-focused workload stacks; those belong in strix-halo-server. Downstream repositories may extend the images published here.

Requirements are grouped by topic; keep closely related requirements together when adding or editing.

## Functional requirements

### Images and variants

- Provide reproducible, bootable single-purpose images that run on any x86_64 system supported by uCore. Do not add hardware-specific kernel arguments, tuned profiles, udev rules, or GPU/AI tooling.
- Keep each image minimal, predictable, and maintainable over time. One image, one purpose. Additional purposes get a new variant, not extra packages in existing images.
- Publish a base image carrying only the shared platform conventions (login account provisioning, rootful Podman enablement, signing trust policy) as a starting point for downstream repositories and user images; it ships no workload services. Variants in this repository build from uCore and share these conventions through `shared/` modules, not from the published base image.
- Follow BlueBuild guidance for shared recipe resources: keep configuration common to all variants in `shared/` as module files included with `from-file:`, with one source of truth. Keep variant-specific recipes, assets, and documentation together under `variants/<name>/`.
- Do not make a published variant a build prerequisite for another variant in this repository; build variants in parallel from the same source revision. Building on an already-published image from this or another repository is allowed.
- Give each published image a distinct, identifiable name prefixed with `single-purpose-os-` and provide a variant-specific README linked from the root README.

### Service deployment

- Enable uCore's rootful `podman-restart.service` in shared configuration so rootful Podman containers with an `always` restart policy restart at boot in every variant.
- For rootful Quadlet services intended to track registry tags, set `AutoUpdate=registry` and enable `podman-auto-update.timer` in the variant; container image updates are separate from bootc OS updates.
- Prefer deploying application workloads as Podman Quadlet units shipped in the image at `/usr/share/containers/systemd/`.
- Base each container unit on the upstream application's official Podman installation instructions (for example, Arcane's Podman setup guide) and express them as a Quadlet following `podman-systemd.unit(5)`; keep the unit in sync with upstream changes and link to them from the variant README.
- systemd should be what starts services. Prefer Quadlet over compose runtimes (docker-compose, podman-compose) and other container lifecycle managers; when Quadlet is a poor fit, podman-compose or docker compose is acceptable (a Quadlet `.compose` unit preferred), started by systemd at boot with its restart policy honored.
- Design image-shipped units to be customizable via official Quadlet drop-ins without editing the image unit. Bake non-secret stable defaults as `Environment=` (drop-ins override per variable); keep secrets and machine-specific values in an `EnvironmentFile` ([decision 0001](DECISIONS.md)). Keep machine-specific settings (bind mounts, extra devices, non-default ports, tunable resource limits) out of image units where a reasonable default exists, and document each supported customization's drop-in path and contents in the variant README.
- Quadlet list keys like `Volume=` accumulate across drop-ins and an empty value resets them; `Environment=` merges per variable. Never instruct users to copy a whole image unit into `/etc` as an override: the copy shadows the image unit and blocks its future updates.
- Enrollment and setup scripts must create an editable default drop-in for common machine-local settings, and must detect settings already supplied by user drop-ins (merged values from `/etc` and `/run` drop-in directories) instead of prompting for or overwriting them.
- Interactive setup after first login is the default for variants with post-install configuration: offer setup at login when its credential file is missing, and let users defer and rerun it.

### Installation and updates

- Support installation onto an existing bootc system with `bootc switch`, and clean bare-metal installation that boots a live environment and installs the selected image with `bootc install to-disk`, ending on that image without a follow-up switch. Any bare-metal path must leave a usable login account on first boot.
- After a bare-metal install, signing in leads to the variant's interactive first-login setup; interactive setup is the default and only documented way to apply machine-specific values and credentials. Do not require a provisioning service or pre-authored configuration files.
- Let users add Quadlet drop-ins during installation: the docs show how to place a drop-in file into the installed system's `/etc` before the first reboot so it is active from first boot.
- Document the bootc installation and update paths in the root README and link to them from every variant README.
- Make routine updates reliable and low-effort: `bootc upgrade` for the operating system and Podman auto-update for application containers, without requiring users to repeat the initial installation.
- Quadlet drop-ins and other configuration under `/etc` are machine-local state and must survive `bootc upgrade` and `bootc switch`; do not rely on anything written under `/usr` persisting across an image update, and do not write machine-specific state into image units.
- Keep deployment and update behavior consistent across supported installation paths, and update the README and this specification when those user-facing workflows change.

## Non-functional requirements

### Ease of adoption and maintenance

- Installing and keeping an image updated must be easier than assembling the same setup by hand on an existing Linux homelab server. Support routine updates without repeating installation.

### Security

- Never bake machine-specific credentials into the image. Keep credentials and machine-specific secrets out of recipes, source files, image builds, and published images; provision secrets on the installed host. Store credentials in root-only host files.

### Reproducibility

- Make container image tags reproducible and identifiable for every variant. Users should be able to follow the `latest` tag or select a specific version tag for repeatable deployment.

### Validation

- Validate every image recipe in CI on pull requests, and publish all variants from the build workflow on merge to `main`. Keep builds independent and parallel.
- Publish images to GHCR with the BlueBuild GitHub action and cosign signing. Do not generate or publish installer ISOs and do not create GitHub Releases in CI; publish identifiable container image tags instead.
- Stage shared BlueBuild file assets into each variant's build context with `scripts/prepare-variant-files.sh` before validation and publishing.
- Sign published images with cosign using the repository's `cosign.pub` key pair, and verify signatures in CI after publishing. The signing secrets (`COSIGN_PRIVATE_KEY`, `COSIGN_PUBLIC_KEY`) are the same values configured in strix-halo-server so the shared trust policy verifies images from both repositories.
- Rebuild images weekly on a schedule to pick up upstream security fixes, in addition to building on merge to `main`.
- Update related user-facing documentation when behavior or supported workflows change.
