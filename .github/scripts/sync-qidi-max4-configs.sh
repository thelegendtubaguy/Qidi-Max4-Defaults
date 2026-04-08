#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <firmware-zip> <destination-config-dir>" >&2
  exit 1
fi

PACKAGE_ZIP=$1
DEST_CONFIG_DIR=$2

if [ ! -f "$PACKAGE_ZIP" ]; then
  echo "Firmware package not found: $PACKAGE_ZIP" >&2
  exit 1
fi

if [ ! -d "$DEST_CONFIG_DIR" ]; then
  echo "Destination config directory not found: $DEST_CONFIG_DIR" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PACKAGE_DIR="$WORK_DIR/package"
SOC_RAW_DIR="$WORK_DIR/soc/raw"
SOC_DATA_DIR="$WORK_DIR/soc/data"

mkdir -p "$PACKAGE_DIR" "$SOC_RAW_DIR" "$SOC_DATA_DIR"

unzip -q "$PACKAGE_ZIP" -d "$PACKAGE_DIR"

MANIFEST_FILE="$PACKAGE_DIR/firmware_manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "firmware_manifest.json not found in $PACKAGE_ZIP" >&2
  exit 1
fi

SOC_PACKAGE_NAME=$(jq -r '.SOC.file // empty' "$MANIFEST_FILE")
if [ -z "$SOC_PACKAGE_NAME" ] || [ "$SOC_PACKAGE_NAME" = "null" ]; then
  echo "SOC package name missing from firmware manifest" >&2
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

DATA_ARCHIVE=""
for candidate in "$SOC_RAW_DIR"/data.tar.*; do
  if [ -f "$candidate" ]; then
    DATA_ARCHIVE=$candidate
    break
  fi
done

if [ -z "$DATA_ARCHIVE" ]; then
  echo "SOC package data archive not found" >&2
  exit 1
fi

tar -xf "$DATA_ARCHIVE" -C "$SOC_DATA_DIR"

SOURCE_CONFIG_DIR="$SOC_DATA_DIR/home/qidi/printer_data/config"
if [ ! -d "$SOURCE_CONFIG_DIR" ]; then
  echo "Extracted config directory not found: $SOURCE_CONFIG_DIR" >&2
  exit 1
fi

rsync -a --delete \
  --exclude 'MCU_ID.cfg' \
  --exclude 'saved_variables.cfg' \
  "$SOURCE_CONFIG_DIR"/ "$DEST_CONFIG_DIR"/

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Extracted Package Sync"
    echo ""
    printf -- '- Source package: `%s`\n' "$(basename "$PACKAGE_ZIP")"
    printf -- '- SOC payload: `%s`\n' "$SOC_PACKAGE_NAME"
    printf -- '- Synced directory: `%s`\n' "$DEST_CONFIG_DIR"
    echo "- Preserved repo-only files: \`MCU_ID.cfg\`, \`saved_variables.cfg\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
