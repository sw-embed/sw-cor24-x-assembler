# Changes

## 2026-03-29

- **BREAKING**: Trimmed repository to assembler-only scope
  - Removed web UI (Yew components, WASM bindings, styles, pages)
  - Removed emulator internals (cpu, emulator, loader, challenge modules)
  - Removed CLI tools (cor24-run, cor24-dbg)
  - Removed rust-to-cor24 translator pipeline
  - Removed ISA crate (now consumed via cor24-emulator dependency)
  - Renamed package from `cor24-emulator` to `cor24-assembler`
  - Added path dependency on `../sw-cor24-emulator` for CPU/ISA types
  - Crate type changed from cdylib+rlib to rlib only
  - 41 unit tests + 20 integration tests pass
  - Added `scripts/build.sh` (build + clippy + test)
