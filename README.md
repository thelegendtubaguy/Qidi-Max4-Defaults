![Tuba Makes](.github/images/tuba-makes-logo.png)

# QIDI Max 4 Firmware Reference

This repository tracks package-owned files shipped in QIDI Max 4 firmware.

Use tags and commit history to compare package revisions.

> [!NOTE]
> If you want to help support content like this, consider subscribing over on [YouTube](https://youtube.com/@TubaMakes)!

## Scope

- `config/` contains the shipped Klipper, Moonraker, Fluidd, macro, box, and preset configuration files.
- `klipper/klippy/` mirrors the complete package-owned `/home/qidi/klipper/klippy/` tree, including Python, config, C, header, and shared-object files.
- `firmware-package.json` records the current SOC version, original firmware archive filename and SHA-256, firmware manifest SHA-256, and SOC payload filename and SHA-256.
- Redacted hardware identifiers in `config/MCU_ID.cfg` stay redacted.
- `config/KAMP/`, `config/MCU_ID.cfg`, `config/saved_variables.cfg`, and `config/fluidd.cfg` are preserved during package synchronization.
- `config/saved_variables.cfg.bak` is not tracked.
- The tracked files are reference material for QIDI's shipped firmware, not a drop-in profile for another machine.

## Firmware Checks

- `.github/workflows/check-qidi-max4-firmware.yml` checks QIDI's firmware endpoint hourly.
- Package identity uses the firmware archive SHA-256; the SOC version does not uniquely identify a package revision.
- Digest-qualified release tags allow multiple package revisions with the same SOC version.
- The scheduled check compares the endpoint archive filename with `firmware-package.json` before downloading the firmware archive.
- A manual run with `download_package` or `publish_release` enabled forces a download when the endpoint reports an update, including when the archive filename is unchanged.
- `.github/scripts/sync-qidi-max4-configs.sh` mirrors `config/` and `klipper/klippy/` with deletion of stale vendor files and updates `firmware-package.json` in the same invocation.
