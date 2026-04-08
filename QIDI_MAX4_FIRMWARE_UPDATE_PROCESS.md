# QIDI Max 4 Firmware Update Format and Install Flow

This note is based on local inspection of `QD_MAX4_01.01.06.02_20260407_Release.zip` and on observed behavior from a printer that ran the update.

## Archive Layout

The update zip contains six top-level files:

- `firmware_manifest.json`
- `QD_MAX4_SOC_01.01.06.02_20260407_Release_NA`
- `QD_MAX4_MCU_02.01.01.11_20260402.bin`
- `QD_MAX4_THR_02.02.01.08_20260303.bin`
- `QD_MAX4_BOX_02.03.01.21_20260124.bin`
- `QD_MAX4_CLOSED_LOOP_03.01.10.13_20251230.bin`

`firmware_manifest.json` ties those payloads together.

## Manifest Contents

| Component | File | Version |
| --- | --- | --- |
| SOC | `QD_MAX4_SOC_01.01.06.02_20260407_Release_NA` | `01.01.06.02` |
| MCU | `QD_MAX4_MCU_02.01.01.11_20260402.bin` | `02.01.01.11` |
| THR | `QD_MAX4_THR_02.02.01.08_20260303.bin` | `02.02.01.08` |
| BOX | `QD_MAX4_BOX_02.03.01.21_20260124.bin` | `02.03.01.21` |
| CLOSED_LOOP_MOTOR | `QD_MAX4_CLOSED_LOOP_03.01.10.13_20251230.bin` | `03.01.10.13` |

## High-Level Update Flow

The client appears to support both online and offline updates.

Observed paths and strings in `qidiclient` indicate this flow:

1. The printer checks QIDI's firmware endpoint at `/backend/v1/fireware/upgrade-info`.
2. Online updates download a zip to `/home/qidi/download/online_update.zip`.
3. Offline updates scan USB storage for `USB/QD_Update/QD_MAX4`.
4. The client extracts the selected zip into `/home/qidi/update/`.
5. The client reads `/home/qidi/update/firmware_manifest.json`.
6. The client validates which components are present and which ones need updating.
7. When the SOC portion is applied, the client appears to install the SOC package with `dpkg -i --force-overwrite`.
8. The client updates THR, BOX, MCU, and closed-loop motor firmware through separate device-specific flows.

The client binary also references a mandatory-offline path at `/home/qidi/printer_data/gcodes/USB/QD_Update/QD_Mandatory_Update.zip`.

## What the SOC Payload Is

The SOC payload is a Debian package.

Package metadata:

- Package: `qd-max4-system`
- Version: `01.01.06.02`
- Architecture: `arm64`
- Description: `Update for QD_MAX4 System`

That package contains both maintainer scripts and a filesystem payload under `/home/qidi`, `/etc`, `/usr`, and `/root`.

## What Gets Shipped Inside the SOC Package

The SOC package contains a full replacement config tree at `/home/qidi/printer_data/config`.

Files present in the inspected package:

- `printer.cfg`
- `box.cfg`
- `crowsnest.conf`
- `drying.conf`
- `moonraker.conf`
- `officiall_filas_list.cfg`
- `timelapse.cfg`
- `saved_variables.cfg.bak`
- `klipper-macros-qd/*.cfg`

It does not ship `MCU_ID.cfg` or `saved_variables.cfg`.

## What the Installer Does Before Unpacking New Files

The SOC `preinst` script does more than a plain file copy.

It:

- backs up Moonraker's SQLite database to `/home/qidi/printer_data/database/moonraker-sql.db.bak`
- deletes `/home/qidi/printer_data/config/klipper-macros-qd`
- removes several Klipper extras and Moonraker components
- removes stale `mcu_box_to_v2_*.bin` files from `/home/qidi/QIDI_Client/tools/`
- removes `/root/QIDILink-client` if present
- stops and removes `/etc/systemd/system/frp.service` if present
- cleans `/home/qidi/printer_data/config`
- cleans `/home/qidi/printer_data/model`
- creates a restore flag when `saved_variables.cfg.bak` is missing
- clears `/tmp`
- stops `algo_app.service` if it is running

## How Config Replacement Appears to Work

The extracted SOC package is not doing a merge.

`preinst` walks `/home/qidi/printer_data/config`, removes every file whose basename is not in the keep list, then removes empty directories.

Keep list in the inspected package:

- `timelapse.cfg`
- `saved_variables.cfg`
- `MCU_ID.cfg`
- `fluidd.cfg`
- `saved_variables.cfg.bak`
- `motion_accuracy_calibration.json`

Important details:

- The keep check uses the basename only, not the full path.
- Extra files and directories under `printer_data/config` are removed unless their basename matches the keep list.
- The package then unpacks a fresh vendor config tree on top of the cleaned directory.
- `timelapse.cfg` is in the keep list, but the package also ships a new `timelapse.cfg`, so it still gets overwritten by package extraction.
- `MCU_ID.cfg` and `saved_variables.cfg` survive because the package does not ship replacements for them.

From the package scripts alone, this looks like a replace-and-preserve process, not a three-way merge.

## Observed On-Printer Behavior

At least one printer that ran this update did **not** match the most destructive interpretation of the extracted `preinst` script.

Observed result:

- `config/KAMP/` was still present after the update.
- The modification times on files inside `KAMP/` did not change.

That means at least one of these must be true:

- the client used an incremental path that did not run the full SOC cleanup path
- the client decided the SOC/config portion did not need to be applied
- the real on-printer install flow differs from a plain `dpkg -i` execution of the extracted package

So the safest conclusion is:

- the extracted package contains destructive cleanup logic
- the real update path on a printer may be more selective than those scripts imply
- package inspection alone is not enough to prove that every extra file under `printer_data/config` is deleted during a real update

## What the Installer Does After Unpacking

The SOC `postinst` script then:

- restores `saved_variables.cfg` from `saved_variables.cfg.bak` if the restore flag exists
- appends any missing keys from `saved_variables.cfg.bak` into `saved_variables.cfg`
- fixes ownership and permissions across config files, Klipper, Moonraker, Fluidd, and QIDI Client files
- restores the Moonraker database from backup if the live database is missing or empty
- enables and starts `qidi-tuning.service` when present
- enables and starts `algo_app.service` when present
- runs `/home/qidi/QIDI_Client/bin/enable-qidi-core-debug.sh`
- appends the installed version to `/home/qidi/iso_version.txt`

## Paths Touched by the SOC Install

The inspected `preinst` and `postinst` scripts touch at least these paths:

- `/home/qidi/printer_data/config`
- `/home/qidi/printer_data/model`
- `/home/qidi/printer_data/database/moonraker-sql.db`
- `/home/qidi/printer_data/database/moonraker-sql.db.bak`
- `/home/qidi/klipper/klippy`
- `/home/qidi/moonraker/moonraker`
- `/home/qidi/fluidd`
- `/home/qidi/QIDI_Client`
- `/home/qidi/mcu_update.sh`
- `/home/qidi/mcu_update_THR.sh`
- `/home/qidi/mcu_update_BOX.sh`
- `/root/Frp`
- `/root/Frp_bak`
- `/root/QIDILink-client`
- `/etc/systemd/system/frpc.service`
- `/etc/systemd/system/qidi-tuning.service`
- `/etc/fstab`
- `/tmp`
- `/var/log/algo_app`
- `/usr/local/bin/algo_app/video_output`
- `/dev_info.txt`
- `/home/qidi/iso_version.txt`

## Repo Sync Implications

For this repo, the most useful part of the package is the extracted `/home/qidi/printer_data/config` tree.

The GitHub Actions workflow extracts that tree from the SOC Debian payload before publishing a firmware release. It updates the repo's shipped config files from the package while preserving a small set of repo-local paths:

- `config/KAMP/`
- `config/MCU_ID.cfg`
- `config/saved_variables.cfg`
- `config/fluidd.cfg`

The repo intentionally does not track `config/saved_variables.cfg.bak`, even though the package ships it and the printer uses it during install.

That keeps the repo aligned with the package contents while preserving the redacted machine identifier include, the saved-variables reference file, the existing Fluidd config, and the repo's `KAMP/` directory.
