#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYNC_SCRIPT="$REPOSITORY_ROOT/.github/scripts/sync-qidi-max4-configs.sh"
CHANGE_DETECTOR="$REPOSITORY_ROOT/.github/scripts/has-qidi-max4-sync-changes.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_content() {
  local expected=$1
  local path=$2
  local actual

  [ -f "$path" ] || fail "missing file: $path"
  actual=$(cat "$path")
  [ "$actual" = "$expected" ] || fail "unexpected content in $path: $actual"
}

assert_absent() {
  [ ! -e "$1" ] || fail "unexpected path exists: $1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

create_firmware_fixture() {
  local fixture_root=$1
  local archive_path=$2
  local revision=$3
  local homing_content=$4
  local mcu_content=$5
  local macro_content=$6
  local soc_name="QD_MAX4_SOC_01.01.06.04_${revision}_Release_NA"
  local package_dir="$fixture_root/package"
  local deb_dir="$fixture_root/deb"
  local data_dir="$fixture_root/data"
  local control_dir="$fixture_root/control"

  mkdir -p \
    "$package_dir" \
    "$deb_dir" \
    "$data_dir/home/qidi/printer_data/config/KAMP" \
    "$data_dir/home/qidi/printer_data/config/klipper-macros-qd" \
    "$data_dir/home/qidi/klipper/klippy/extras" \
    "$data_dir/home/qidi/klipper/klippy/chelper" \
    "$control_dir"

  printf '%s\n' 'vendor printer config' > "$data_dir/home/qidi/printer_data/config/printer.cfg"
  printf '%s\n' 'vendor KAMP content' > "$data_dir/home/qidi/printer_data/config/KAMP/vendor.cfg"
  printf '%s\n' 'UNREDACTED-HARDWARE-ID' > "$data_dir/home/qidi/printer_data/config/MCU_ID.cfg"
  printf '%s\n' 'vendor saved variables' > "$data_dir/home/qidi/printer_data/config/saved_variables.cfg"
  printf '%s\n' 'vendor Fluidd config' > "$data_dir/home/qidi/printer_data/config/fluidd.cfg"
  printf '%s\n' 'vendor backup' > "$data_dir/home/qidi/printer_data/config/saved_variables.cfg.bak"
  printf '%s\n' "$macro_content" > "$data_dir/home/qidi/printer_data/config/klipper-macros-qd/qd_macro.cfg"

  printf '%s\n' "$homing_content" > "$data_dir/home/qidi/klipper/klippy/extras/homing.py"
  printf '%s\n' "$mcu_content" > "$data_dir/home/qidi/klipper/klippy/mcu.py"
  printf '%s\n' '[fixture]' > "$data_dir/home/qidi/klipper/klippy/extras/fixture.cfg"
  printf '%s\n' 'int fixture(void) { return 1; }' > "$data_dir/home/qidi/klipper/klippy/chelper/fixture.c"
  printf '%s\n' 'int fixture(void);' > "$data_dir/home/qidi/klipper/klippy/chelper/fixture.h"
  printf '\177ELF\000fixture-binary\377' > "$data_dir/home/qidi/klipper/klippy/chelper/fixture.so"
  chmod 755 "$data_dir/home/qidi/klipper/klippy/chelper/fixture.so"

  cat > "$control_dir/control" <<'CONTROL'
Package: qd-max4-system
Version: 01.01.06.04
Architecture: arm64
Maintainer: QIDI
Description: Synthetic firmware sync fixture
CONTROL

  printf '2.0\n' > "$deb_dir/debian-binary"
  COPYFILE_DISABLE=1 tar -czf "$deb_dir/control.tar.gz" -C "$control_dir" .
  COPYFILE_DISABLE=1 tar -czf "$deb_dir/data.tar.gz" -C "$data_dir" .
  python3 - "$deb_dir" "$package_dir/$soc_name" <<'PYTHON'
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])

with destination.open("wb") as archive:
    archive.write(b"!<arch>\n")
    for name in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        data = (source / name).read_bytes()
        header = (
            f"{name:<16}"
            f"{0:<12}"
            f"{0:<6}"
            f"{0:<6}"
            f"{0o100644:<8o}"
            f"{len(data):<10}"
            "`\n"
        ).encode("ascii")
        archive.write(header)
        archive.write(data)
        if len(data) % 2:
            archive.write(b"\n")
PYTHON

  jq -n \
    --arg soc_file "$soc_name" \
    '{SOC: {file: $soc_file, version: "01.01.06.04", region: "NA"}}' \
    > "$package_dir/firmware_manifest.json"

  (
    cd "$package_dir"
    zip -q -X "$archive_path" firmware_manifest.json "$soc_name"
  )
}

WORK_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

DESTINATION="$WORK_DIR/repository"
ARCHIVE_ONE="$WORK_DIR/QD_MAX4_01.01.06.04_20260609_Release.zip"
ARCHIVE_TWO="$WORK_DIR/QD_MAX4_01.01.06.04_20260612_Release_NA.zip"

mkdir -p \
  "$DESTINATION/config/KAMP" \
  "$DESTINATION/klipper/klippy/extras"
printf '%s\n' 'repo KAMP content' > "$DESTINATION/config/KAMP/local.cfg"
printf '%s\n' '[REDACTED-HARDWARE-ID]' > "$DESTINATION/config/MCU_ID.cfg"
printf '%s\n' 'repo saved variables' > "$DESTINATION/config/saved_variables.cfg"
printf '%s\n' 'repo Fluidd config' > "$DESTINATION/config/fluidd.cfg"
printf '%s\n' 'stale vendor config' > "$DESTINATION/config/stale.cfg"
printf '%s\n' 'stale Klippy source' > "$DESTINATION/klipper/klippy/extras/stale.py"

create_firmware_fixture \
  "$WORK_DIR/fixture-one" \
  "$ARCHIVE_ONE" \
  '20260609' \
  'homing revision one' \
  'mcu revision one' \
  'macro revision one'

bash "$SYNC_SCRIPT" "$ARCHIVE_ONE" "$DESTINATION"

assert_file_content 'vendor printer config' "$DESTINATION/config/printer.cfg"
assert_file_content 'repo KAMP content' "$DESTINATION/config/KAMP/local.cfg"
assert_file_content '[REDACTED-HARDWARE-ID]' "$DESTINATION/config/MCU_ID.cfg"
assert_file_content 'repo saved variables' "$DESTINATION/config/saved_variables.cfg"
assert_file_content 'repo Fluidd config' "$DESTINATION/config/fluidd.cfg"
assert_absent "$DESTINATION/config/KAMP/vendor.cfg"
assert_absent "$DESTINATION/config/stale.cfg"
assert_absent "$DESTINATION/config/saved_variables.cfg.bak"
assert_absent "$DESTINATION/klipper/klippy/extras/stale.py"
assert_file_content 'homing revision one' "$DESTINATION/klipper/klippy/extras/homing.py"
assert_file_content 'mcu revision one' "$DESTINATION/klipper/klippy/mcu.py"

EXPECTED_BINARY="$WORK_DIR/expected.so"
printf '\177ELF\000fixture-binary\377' > "$EXPECTED_BINARY"
cmp "$EXPECTED_BINARY" "$DESTINATION/klipper/klippy/chelper/fixture.so" \
  || fail 'binary Klippy file was not preserved byte-for-byte'
[ -x "$DESTINATION/klipper/klippy/chelper/fixture.so" ] \
  || fail 'executable mode was not preserved for binary Klippy file'

ARCHIVE_ONE_SHA=$(sha256_file "$ARCHIVE_ONE")
SOC_ONE_NAME=$(jq -r '.SOC.file' "$WORK_DIR/fixture-one/package/firmware_manifest.json")
SOC_ONE_SHA=$(sha256_file "$WORK_DIR/fixture-one/package/$SOC_ONE_NAME")
[ "$(jq -r '.soc_version' "$DESTINATION/firmware-package.json")" = '01.01.06.04' ] \
  || fail 'SOC version missing from package identity'
[ "$(jq -r '.firmware_archive.filename' "$DESTINATION/firmware-package.json")" = "$(basename "$ARCHIVE_ONE")" ] \
  || fail 'archive filename missing from package identity'
[ "$(jq -r '.firmware_archive.sha256' "$DESTINATION/firmware-package.json")" = "$ARCHIVE_ONE_SHA" ] \
  || fail 'archive SHA-256 missing from package identity'
[ "$(jq -r '.soc_payload.filename' "$DESTINATION/firmware-package.json")" = "$SOC_ONE_NAME" ] \
  || fail 'SOC payload filename missing from package identity'
[ "$(jq -r '.soc_payload.sha256' "$DESTINATION/firmware-package.json")" = "$SOC_ONE_SHA" ] \
  || fail 'SOC payload SHA-256 missing from package identity'

IDENTITY_SHA_BEFORE=$(sha256_file "$DESTINATION/firmware-package.json")
bash "$SYNC_SCRIPT" "$ARCHIVE_ONE" "$DESTINATION"
IDENTITY_SHA_AFTER=$(sha256_file "$DESTINATION/firmware-package.json")
[ "$IDENTITY_SHA_BEFORE" = "$IDENTITY_SHA_AFTER" ] \
  || fail 'package identity output is not deterministic'

create_firmware_fixture \
  "$WORK_DIR/fixture-two" \
  "$ARCHIVE_TWO" \
  '20260612' \
  'homing revision two with endstop reset' \
  'mcu revision two with endstop_sync_reset' \
  'macro revision two'

bash "$SYNC_SCRIPT" "$ARCHIVE_TWO" "$DESTINATION"

assert_file_content 'homing revision two with endstop reset' "$DESTINATION/klipper/klippy/extras/homing.py"
assert_file_content 'mcu revision two with endstop_sync_reset' "$DESTINATION/klipper/klippy/mcu.py"
assert_file_content 'macro revision two' "$DESTINATION/config/klipper-macros-qd/qd_macro.cfg"
[ "$(jq -r '.soc_version' "$DESTINATION/firmware-package.json")" = '01.01.06.04' ] \
  || fail 'same-version package revision changed the SOC version unexpectedly'
[ "$(jq -r '.firmware_archive.sha256' "$DESTINATION/firmware-package.json")" = "$(sha256_file "$ARCHIVE_TWO")" ] \
  || fail 'same-version package revision did not update archive identity'

DETECTION_REPOSITORY="$WORK_DIR/change-detection"
mkdir -p "$DETECTION_REPOSITORY/config" "$DETECTION_REPOSITORY/klipper/klippy"
printf '%s\n' 'config baseline' > "$DETECTION_REPOSITORY/config/printer.cfg"
printf '%s\n' 'Klippy baseline' > "$DETECTION_REPOSITORY/klipper/klippy/mcu.py"
printf '%s\n' '{}' > "$DETECTION_REPOSITORY/firmware-package.json"
(
  cd "$DETECTION_REPOSITORY"
  git init -q
  git add config klipper/klippy firmware-package.json
  TREE=$(git write-tree)
  COMMIT=$(printf 'tree %s\nauthor Firmware Sync Test <firmware-sync@invalid.invalid> 0 +0000\ncommitter Firmware Sync Test <firmware-sync@invalid.invalid> 0 +0000\n\nbaseline\n' "$TREE" \
    | git hash-object -t commit -w --stdin)
  git update-ref HEAD "$COMMIT"
)

if bash "$CHANGE_DETECTOR" "$DETECTION_REPOSITORY"; then
  fail 'clean sync paths were reported as changed'
fi

printf '%s\n' 'Klippy-only change' > "$DETECTION_REPOSITORY/klipper/klippy/mcu.py"
bash "$CHANGE_DETECTOR" "$DETECTION_REPOSITORY" \
  || fail 'Klippy-only change was not detected by workflow path logic'

grep -Fq 'if ! bash .github/scripts/has-qidi-max4-sync-changes.sh; then' \
  "$REPOSITORY_ROOT/.github/workflows/check-qidi-max4-firmware.yml" \
  || fail 'firmware workflow does not use the tested sync change detector'
grep -Fq 'git add -A -- config klipper/klippy firmware-package.json' \
  "$REPOSITORY_ROOT/.github/workflows/check-qidi-max4-firmware.yml" \
  || fail 'firmware workflow does not stage every synchronized path'

printf '%s\n' 'PASS: firmware sync fixtures'
