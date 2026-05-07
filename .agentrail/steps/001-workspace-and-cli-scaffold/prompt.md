Convert the top-level Cargo.toml to a Cargo workspace and add a `cli/` subcrate that builds a `cor24-asm` binary stub.

Concretely:

1. Add a `[workspace]` table to `/disk1/github/softwarewrighter/devgroup/work/dcxas/github/sw-embed/sw-cor24-x-assembler/Cargo.toml` with `members = [".", "cli"]` and `resolver = "2"`. Keep the existing `[package]`, `[lib]`, `[dependencies]`, and `[profile.release]` blocks untouched — the lib crate stays a member.

2. Create `cli/Cargo.toml`:
   - `name = "cor24-asm-cli"`
   - `[[bin]]` named `cor24-asm`
   - depend on the local lib (`cor24-assembler = { path = ".." }`)
   - edition matches the lib (`2024`)
   - same author/license/version metadata for now

3. Create `cli/src/main.rs` with a minimal stub that prints "cor24-asm: not yet implemented" and returns exit 0 — placeholder until step 4. Real arg parsing comes in step 4.

4. Verify:
   - `cargo build --workspace` succeeds
   - `cargo clippy --workspace -- -D warnings` succeeds
   - `cargo test --workspace` still passes (no new tests yet)

5. Do NOT edit `scripts/build.sh` yet — that's part of step 6.

6. Commit on `feat/cor24-asm-cli`. Include `.agentrail/` changes (saga init + this step's begin/complete) in the same commit per CLAUDE.md.
