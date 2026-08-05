#!/usr/bin/env python3
import argparse
from pathlib import Path

TEXT_SUFFIXES = {".c", ".cfg", ".conf", ".h", ".json", ".py"}


def normalized(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n")


def newline_style(data: bytes) -> str | None:
    crlf_count = data.count(b"\r\n")
    lf_count = data.count(b"\n") - crlf_count
    bare_cr_count = data.count(b"\r") - crlf_count

    if bare_cr_count:
        return None
    if crlf_count and not lf_count:
        return "crlf"
    if lf_count and not crlf_count:
        return "lf"
    return None


def reconcile_tree(source_root: Path, destination_root: Path) -> tuple[int, int]:
    retained = 0
    harmonized = 0

    for source in source_root.rglob("*"):
        if source.is_symlink() or not source.is_file():
            continue
        if source.suffix.lower() not in TEXT_SUFFIXES:
            continue

        destination = destination_root / source.relative_to(source_root)
        if destination.is_symlink() or not destination.is_file():
            continue

        source_data = source.read_bytes()
        destination_data = destination.read_bytes()
        if b"\0" in source_data or b"\0" in destination_data:
            continue

        normalized_source = normalized(source_data)
        if normalized_source == normalized(destination_data):
            if source_data != destination_data:
                source.write_bytes(destination_data)
                retained += 1
            continue

        source_style = newline_style(source_data)
        destination_style = newline_style(destination_data)
        if source_style is None or destination_style is None:
            continue
        if source_style == destination_style:
            continue

        if destination_style == "crlf":
            reconciled = normalized_source.replace(b"\n", b"\r\n")
        else:
            reconciled = normalized_source

        source.write_bytes(reconciled)
        harmonized += 1

    return retained, harmonized


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", type=Path)
    parser.add_argument("destination_root", type=Path)
    args = parser.parse_args()

    retained, harmonized = reconcile_tree(args.source_root, args.destination_root)
    print(
        "Line-ending reconciliation: "
        f"retained {retained} unchanged files; harmonized {harmonized} changed files"
    )


if __name__ == "__main__":
    main()
