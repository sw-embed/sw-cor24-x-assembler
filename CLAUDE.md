# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Overview

`sw-cor24-assembler` is a Rust library that parses COR24 assembly language and produces machine code. It depends on `cor24-emulator` for ISA definitions and CPU types.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Build Commands

```bash
# Full check: build + clippy + test
./scripts/build.sh

# Individual commands
cargo build
cargo clippy -- -D warnings
cargo test
```

## Architecture

- **`src/assembler.rs`** — Two-pass assembler producing machine code from COR24 assembly
- **`src/lib.rs`** — Crate root, re-exports `Assembler`, `AssemblyResult`, `AssembledLine`
- **`tests/`** — Integration tests (assemble + execute via emulator)
- **`docs/examples/`** — Assembly example files used by tests
- **`src/examples/assembler/`** — More assembly examples

## Dependencies

- `cor24-emulator` (path: `../sw-cor24-emulator`) — CPU types, ISA, executor
- `serde` — Serialization for assembly results

## Commit Discipline

Commit early and often. Each commit should do one thing. Run `cargo clippy -- -D warnings` and `cargo test` before committing.
