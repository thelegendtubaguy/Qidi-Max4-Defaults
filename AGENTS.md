# AGENTS.md

## Repo Purpose

- This repo tracks the QIDI Max 4 configs QIDI is shipping.

## Rules

- Never modify `config/fluidd.cfg`; it is read-only on the printer.
- If a change would normally go in `config/fluidd.cfg`, implement it in another file under `config/`.
- Preserve machine-specific and vendor-specific behavior unless the user explicitly asks to change it.
- Keep redacted hardware identifiers redacted.
