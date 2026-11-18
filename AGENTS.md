# Project Specification

This repository defines single-purpose bootable container images for homelab servers. Each published image is a small, focused, self-contained system: a uCore (Fedora CoreOS) base plus one purpose, updated through bootc. The root [README.md](README.md) catalogs the images and links to image-specific installation and administration instructions.

This repository is the hardware-neutral sibling of [strix-halo-server](https://github.com/BryanConradHart/strix-halo-server). Keep it free of hardware-specific kernel arguments and free of AI-focused workload stacks; those belong in strix-halo-server. Downstream repositories may extend the images published here.

## Product requirements

- Provide reproducible, bootable single-purpose images that run on any x86_64 system supported by uCore. Do not add hardware-specific kernel arguments, tuned profiles, udev rules, or GPU/AI tooling.
- Keep each image minimal, predictable, and maintainable over time. One image, one purpose. Additional purposes get a new variant, not extra packages in existing images.
- Follow BlueBuild guidance for shared recipe resources: keep configuration common to all variants in `shared/` as module files included with `from-file:`, with one source of truth. Keep variant-specific recipes, assets, and documentation together under `variants/<name>/`.
- Do not make a published variant a build prerequisite for another variant in this repository; build variants in parallel from the same source revision. Building on an already-published image from this or another repository is allowed.
- Enable uCore's rootful `podman-restart.service` in shared configuration so rootful Podman containers with an `always` restart policy restart at boot in every variant.
- For rootful Quadlet services intended to track registry tags, set `AutoUpdate=registry` and enable `podman-auto-update.timer` in the variant; container image updates are separate from bootc OS updates.
- Give each published image a distinct, identifiable name prefixed with `single-purpose-os-` and provide a variant-specific README linked from the root README.
- Treat ease of adoption and maintenance as a product requirement: installing and keeping an image updated must be easier than assembling the same setup by hand on an existing Linux homelab server. Support routine updates without repeating installation. Never bake machine-specific credentials into the image.
- Interactive setup after first login is the default for variants with post-install configuration: offer setup at login when its credential file is missing, and let users defer and rerun it. Store credentials in root-only host files, never in the image.
- Document the bootc installation and update paths in the root README and link to them from every variant README.

## Deployment and lifecycle requirements

- Publish images to GHCR with the BlueBuild GitHub action and cosign signing. Do not generate or publish installer ISOs and do not create GitHub Releases in CI; publish identifiable container image tags instead.
- Make container image tags reproducible and identifiable for every variant. Users should be able to follow the `latest` tag or select a specific version tag for repeatable deployment.
- Make routine updates reliable and low-effort: `bootc upgrade` for the operating system and Podman auto-update for application containers, without requiring users to repeat the initial installation.
- Rebuild images weekly on a schedule to pick up upstream security fixes, in addition to building on merge to `main`.
- Keep deployment and update behavior consistent across supported installation paths, and update the README and this specification when those user-facing workflows change.

## CI and validation guidelines

- Validate every image recipe in CI on pull requests, and publish all variants from the build workflow on merge to `main`. Keep builds independent and parallel.
- Stage shared BlueBuild file assets into each variant's build context with `scripts/prepare-variant-files.sh` before validation and publishing.
- Sign published images with cosign using the repository's `cosign.pub` key pair, and verify signatures in CI after publishing. The signing secrets (`COSIGN_PRIVATE_KEY`, `COSIGN_PUBLIC_KEY`) are the same values configured in strix-halo-server so the shared trust policy verifies images from both repositories.
- Keep credentials and machine-specific secrets out of recipes, source files, image builds, and published images. Provision secrets on the installed host.
- Update related user-facing documentation when behavior or supported workflows change.
