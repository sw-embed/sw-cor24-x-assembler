Update the README and build script to reflect the new CLI surface.

README (`/disk1/github/softwarewrighter/devgroup/work/dcxas/github/sw-embed/sw-cor24-x-assembler/README.md`):

- Rename the existing `## Usage` section to `## Library Usage` and keep the existing Rust example.
- Add a new `## CLI` section ABOVE the library usage (CLI is the primary interface for non-Rust consumers and downstream tooling). Include:
  - one-sentence summary noting `cor24-asm` is the canonical command for `.s → .lgo`
  - the four invocation forms (default, -o, --bin/--listing, stdin/stdout)
  - exit codes 0 / 1 / 2
  - example: `cor24-asm prog.s` produces `prog.lgo`; `cor24-asm prog.s --bin prog.bin --listing prog.lst -o prog.lgo` produces all three.
- Add a brief mention under `## Build` that `./scripts/build.sh` produces the `cor24-asm` binary at `target/<profile>/cor24-asm`.

Build script (`/disk1/github/softwarewrighter/devgroup/work/dcxas/github/sw-embed/sw-cor24-x-assembler/scripts/build.sh`):

- Currently runs `cargo build`, `cargo clippy -- -D warnings`, `cargo test`. Without `--workspace`, those run only on the root package and skip the new cli crate.
- Update each cargo invocation to use `--workspace` so the cli crate is built/checked/tested too. Keep the headings.

Verify after editing:
- `./scripts/build.sh` runs to completion with all green
- `target/debug/cor24-asm --help` works (proves the bin built)

Commit with `docs:` prefix and include `.agentrail/` deltas.