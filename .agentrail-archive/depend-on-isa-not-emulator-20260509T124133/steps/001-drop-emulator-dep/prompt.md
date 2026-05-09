Drop `cor24-emulator` as a compile-time dep; add `cor24-isa` as the direct path-dep. The emulator stays as a `dev-dependency` for tests that round-trip through `load_lgo` and execute machine code via `Executor`.

1. **Top-level `Cargo.toml`** — replace:
   ```toml
   [dependencies]
   cor24-emulator = { path = "../sw-cor24-emulator" }
   serde = { version = "1.0", features = ["derive"] }
   serde_json = "1.0"
   ```
   with:
   ```toml
   [dependencies]
   cor24-isa = { path = "../sw-cor24-isa" }
   serde = { version = "1.0", features = ["derive"] }
   serde_json = "1.0"

   [dev-dependencies]
   cor24-emulator = { path = "../sw-cor24-emulator" }
   ```

2. **`src/lib.rs`** — remove the `pub use cor24_emulator;` line (whatever line number it lands on after step 1's stable layout). Drop also the comment immediately above it ("Re-export emulator types..."). The other re-exports stay.

3. **`src/assembler.rs`** — top-of-file imports at lines 6-7:
   ```rust
   use cor24_emulator::cpu::encode;
   use cor24_emulator::cpu::instruction::Opcode;
   ```
   become:
   ```rust
   use cor24_isa::encode;
   use cor24_isa::Opcode;
   ```
   (Use the short `cor24_isa::Opcode` re-export; cor24_isa/src/lib.rs has `pub use opcode::{... Opcode};` at its top.)

4. **Test imports remain unchanged.** Verify (don't edit):
   - `src/lgo.rs:45-46`: `use cor24_emulator::cpu::state::CpuState;` and `use cor24_emulator::loader::load_lgo;` are inside `#[cfg(test)] mod tests` — they stay; resolve via dev-deps.
   - `src/assembler.rs:1154, 1180, 1225`: `cor24_emulator::cpu::{CpuState, Executor, ExecuteResult}` are inside `#[test] fn test_led_blink_integration` and `#[test] fn test_branch_loop_integration` — they stay; resolve via dev-deps.

5. **README.md** — update the `## Dependencies` section. Today it lists `sw-cor24-emulator — ISA definitions and CPU types`. After this change, the dep is split: `sw-cor24-isa — ISA definitions (opcodes, encoding tables, branch constants)` for compile-time, and `sw-cor24-emulator — runtime types (CpuState, Executor) used in round-trip tests` as a dev-dep. Reword the section to reflect that.

6. **Verify the brief's full check** runs clean:
   ```bash
   cargo build --workspace --release
   cargo test --workspace
   cargo clippy --workspace --all-targets --all-features -- -D warnings
   target/release/cor24-asm -V
   ```

7. Commit with the exact message from the brief:
   ```
   refactor: depend on cor24-isa directly instead of cor24-emulator

   The assembler's runtime types (Opcode, encode) live in cor24-isa,
   not the emulator. Switching to a direct path-dep eliminates the
   emulator from compile-time deps; it remains a dev-dep for the
   .lgo round-trip tests in src/lgo.rs.

   Removes the pub use cor24_emulator anti-pattern from src/lib.rs.
   ```
   Include `.agentrail/` deltas (saga init + this step's begin/complete).

8. `agentrail complete --done`. `dg-mark-pr`. STOP.
