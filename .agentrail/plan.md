# Saga: cor24-asm-cli

## Goal

Add a `cor24-asm` CLI binary to `sw-cor24-x-assembler` that takes COR24
assembly text and produces three optional output artifacts: `.lgo` (default),
`.bin`, and `.lst` (listing). This consolidates "assemble" responsibility
in this binary so `cor24-emu`'s `--run` and `--assemble` modes can be
removed in dcemu's follow-up saga (`pr/remove-internal-assembler`).

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-cor24-asm-cli.md

## Architectural boundary

- `.lgo` reader/loader → `sw-cor24-emulator` (stays put).
- `.lgo` / `.bin` / `.lst` writers → here, in `sw-cor24-x-assembler`.
- This crate must NOT take a hard dep on `cor24_emulator::assembler` symbols;
  dcemu's follow-up saga deletes that module.

## Design defaults

- `.lgo` writer: 36 data bytes per `L` line (matches existing fixtures
  `count_down.lgo`, `hello_world.lgo`).
- `.lgo` G-line policy: never emit in this PR. Downstream uses
  `cor24-emu --lgo` which doesn't require G. A future `--entry` flag can
  add G emission if/when needed.
- `.lst` listing: byte-for-byte match the emulator's existing emitter at
  `sw-cor24-emulator/cli/src/run.rs:1602-1617`, including the 1-col offset
  quirk between bytes-line and source-only-line branches (don't normalize).

## Steps (planned)

1. **workspace-and-cli-scaffold** — convert top-level Cargo.toml to a
   workspace, add `cli/` subcrate with `Cargo.toml` (`name =
   "cor24-asm-cli"`, `[[bin]] name = "cor24-asm"`) and a stub `main.rs`.
   Confirm `cargo build --workspace` and `cargo clippy --workspace -- -D
   warnings` pass.
2. **lgo-writer** — new `src/lgo.rs` with `pub fn write(bytes: &[u8],
   base_addr: u32, entry: Option<u32>, w: &mut impl io::Write) ->
   io::Result<()>`. Round-trip test through `cor24_emulator::loader`.
3. **listing-writer** — new `src/listing.rs` with `pub fn
   write(result: &AssemblyResult, w: &mut impl io::Write) ->
   io::Result<()>`. Fixture test against a known-good listing string.
4. **cli-binary** — `cli/src/main.rs`: positional input (file or `-`),
   `-o`/`--bin`/`--listing` outputs, `-V`/`-h`, exit codes 0/1/2, TTY
   refusal for binary outputs, vergen version block mirroring `cor24-dbg`.
5. **cli-integration-tests** — `cli/tests/cli.rs` (or top-level
   `tests/cli.rs`). Cover default `<stem>.lgo`, `-o`, `--bin`, all-three
   combo, stdin/stdout pipe round-trip for `.lgo`, broken input → exit 1,
   missing input → exit 2, `-V` parses cleanly.
6. **readme-and-build-script** — README adds CLI section, renames "Usage"
   to "Library Usage". `scripts/build.sh` builds the workspace.

## Out of scope

- No changes to `sw-cor24-emulator`.
- No language-toolchain orchestrator (`devgroup/tools/build-all`).
- Phases 2-3 of the assembler roadmap (`sw-cor24-hlasm`, self-hosting).

## When done

`dg-mark-pr` to rename `feat/cor24-asm-cli` → `pr/cor24-asm-cli`. Mike
relays via `dg-relay dcxas sw-cor24-x-assembler pr/cor24-asm-cli`.
