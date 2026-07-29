#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <firmware-zip> <repository-root>" >&2
  exit 1
fi

PACKAGE_ZIP=$1
REPOSITORY_ROOT=$2
DEST_CONFIG_DIR="$REPOSITORY_ROOT/config"
DEST_KLIPPY_DIR="$REPOSITORY_ROOT/klipper/klippy"
PACKAGE_IDENTITY_FILE="$REPOSITORY_ROOT/firmware-package.json"

if [ ! -f "$PACKAGE_ZIP" ]; then
  echo "Firmware package not found: $PACKAGE_ZIP" >&2
  exit 1
fi

if [ ! -d "$REPOSITORY_ROOT" ]; then
  echo "Repository root not found: $REPOSITORY_ROOT" >&2
  exit 1
fi

if [ ! -d "$DEST_CONFIG_DIR" ]; then
  echo "Destination config directory not found: $DEST_CONFIG_DIR" >&2
  exit 1
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

WORK_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PACKAGE_DIR="$WORK_DIR/package"
SOC_RAW_DIR="$WORK_DIR/soc/raw"
SOC_DATA_DIR="$WORK_DIR/soc/data"
PACKAGE_IDENTITY_TEMP="$WORK_DIR/firmware-package.json"

mkdir -p "$PACKAGE_DIR" "$SOC_RAW_DIR" "$SOC_DATA_DIR"

unzip -q "$PACKAGE_ZIP" -d "$PACKAGE_DIR"

MANIFEST_FILE="$PACKAGE_DIR/firmware_manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "firmware_manifest.json not found in $PACKAGE_ZIP" >&2
  exit 1
fi

SOC_PACKAGE_NAME=$(jq -r '.SOC.file // empty' "$MANIFEST_FILE")
SOC_VERSION=$(jq -r '.SOC.version // empty' "$MANIFEST_FILE")
SOC_REGION=$(jq -r '.SOC.region // empty' "$MANIFEST_FILE")

if [ -z "$SOC_PACKAGE_NAME" ] || [ "$SOC_PACKAGE_NAME" = "null" ]; then
  echo "SOC package name missing from firmware manifest" >&2
  exit 1
fi

if [ -z "$SOC_VERSION" ] || [ "$SOC_VERSION" = "null" ]; then
  echo "SOC version missing from firmware manifest" >&2
  exit 1
fi

SOC_PACKAGE_PATH="$PACKAGE_DIR/$SOC_PACKAGE_NAME"
if [ ! -f "$SOC_PACKAGE_PATH" ]; then
  echo "SOC package listed in manifest not found: $SOC_PACKAGE_PATH" >&2
  exit 1
fi

cp "$SOC_PACKAGE_PATH" "$SOC_RAW_DIR/qidi-max4-soc.deb"

(
  cd "$SOC_RAW_DIR"
  ar x "qidi-max4-soc.deb"
)

shopt -s nullglob
DATA_ARCHIVES=("$SOC_RAW_DIR"/data.tar.*)
shopt -u nullglob

if [ "${#DATA_ARCHIVES[@]}" -ne 1 ]; then
  echo "Expected one SOC package data archive, found ${#DATA_ARCHIVES[@]}" >&2
  exit 1
fi

DATA_ARCHIVE=${DATA_ARCHIVES[0]}
tar -xf "$DATA_ARCHIVE" -C "$SOC_DATA_DIR"

SOURCE_CONFIG_DIR="$SOC_DATA_DIR/home/qidi/printer_data/config"
SOURCE_KLIPPY_DIR="$SOC_DATA_DIR/home/qidi/klipper/klippy"

if [ ! -d "$SOURCE_CONFIG_DIR" ]; then
  echo "Extracted config directory not found: $SOURCE_CONFIG_DIR" >&2
  exit 1
fi

if [ ! -d "$SOURCE_KLIPPY_DIR" ]; then
  echo "Extracted Klippy directory not found: $SOURCE_KLIPPY_DIR" >&2
  exit 1
fi

ARCHIVE_FILENAME=$(basename "$PACKAGE_ZIP")
ARCHIVE_SHA256=$(sha256_file "$PACKAGE_ZIP")
MANIFEST_SHA256=$(sha256_file "$MANIFEST_FILE")
SOC_PACKAGE_SHA256=$(sha256_file "$SOC_PACKAGE_PATH")

jq -n \
  --arg archive_filename "$ARCHIVE_FILENAME" \
  --arg archive_sha256 "$ARCHIVE_SHA256" \
  --arg manifest_sha256 "$MANIFEST_SHA256" \
  --arg soc_filename "$SOC_PACKAGE_NAME" \
  --arg soc_sha256 "$SOC_PACKAGE_SHA256" \
  --arg soc_version "$SOC_VERSION" \
  --arg soc_region "$SOC_REGION" \
  '{
    schema_version: 1,
    soc_version: $soc_version,
    firmware_archive: {
      filename: $archive_filename,
      sha256: $archive_sha256
    },
    firmware_manifest: {
      sha256: $manifest_sha256
    },
    soc_payload: {
      filename: $soc_filename,
      sha256: $soc_sha256,
      region: $soc_region
    }
  }' > "$PACKAGE_IDENTITY_TEMP"

mkdir -p "$DEST_KLIPPY_DIR"

rsync -a --checksum --delete \
  --exclude 'KAMP/' \
  --exclude 'MCU_ID.cfg' \
  --exclude 'saved_variables.cfg' \
  --exclude 'fluidd.cfg' \
  "$SOURCE_CONFIG_DIR"/ "$DEST_CONFIG_DIR"/

rm -f "$DEST_CONFIG_DIR/saved_variables.cfg.bak"

rsync -a --checksum --delete "$SOURCE_KLIPPY_DIR"/ "$DEST_KLIPPY_DIR"/

mv "$PACKAGE_IDENTITY_TEMP" "$PACKAGE_IDENTITY_FILE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Extracted Package Sync"
    echo ""
    printf -- "- Firmware archive: \`%s\` (\`%s\`)\n" "$ARCHIVE_FILENAME" "$ARCHIVE_SHA256"
    printf -- "- SOC version: \`%s\`\n" "$SOC_VERSION"
    printf -- "- SOC payload: \`%s\` (\`%s\`)\n" "$SOC_PACKAGE_NAME" "$SOC_PACKAGE_SHA256"
    printf -- "- Synced config directory: \`%s\`\n" "$DEST_CONFIG_DIR"
    printf -- "- Synced Klippy directory: \`%s\`\n" "$DEST_KLIPPY_DIR"
    printf -- "- Package identity: \`%s\`\n" "$PACKAGE_IDENTITY_FILE"
    echo "- Preserved config paths: \`KAMP/\`, \`MCU_ID.cfg\`, \`saved_variables.cfg\`, \`fluidd.cfg\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
