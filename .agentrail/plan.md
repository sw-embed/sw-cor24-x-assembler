# Saga: cor24-asm-base-addr

## Goal

Add `--base-addr <addr>` to the `cor24-asm` CLI so the binary can
match what the deprecated `cor24-run --assemble --base-addr` did.
This unblocks dcpls's two pass-2 reassembly callsites in
`pr/bootstrap-toolchain` (linker tests) currently TODO'd against
`cor24-asm`.

Brief: /disk1/github/softwarewrighter/devgroup/tools/briefs/dcxas-cor24-asm-base-addr.md
Reference: `git show ba96d75` in sw-cor24-emulator (original
`--base-addr` impl, before dcemu's removal saga deleted it).

## Library backing

Already present in `src/assembler.rs`:
- `pub fn assemble_at(&mut self, source: &str, base_address: u32) -> AssemblyResult`
- `AssembledLine.address` is **absolute** (base_addr + offset).
- Five existing tests cover assemble_at semantics
  (`test_assemble_at_*`).

`src/lgo.rs::write` already takes `base_addr: u32` and emits
`L<base+chunk_offset>...` records. Just needs the CLI to pass it
through (currently hard-coded `0`).

`src/listing.rs` writes `{:04X}` of `line.address`, which is
already absolute — no change needed.

## Design

- Numeric address parser mirrors the reference impl: `0x` prefix,
  trailing `h` suffix, or decimal. Rejects everything else with
  exit 2.
- CLI default: `0` (no regression vs current behavior).
- New helper `parse_numeric_addr(s: &str) -> Option<u32>` in main.rs.

## Steps (planned)

1. **archive-and-cli-plumbing** — archive prior saga (already done
   pre-init), init this saga, add `--base-addr` flag to
   `cli/src/main.rs` (parser + `Cli.base_addr` field +
   `parse_numeric_addr` helper + USAGE update), swap
   `asm.assemble(&source)` to `asm.assemble_at(&source,
   cli.base_addr)`, plumb `cli.base_addr` into `lgo::write` calls.
   Smoke-test with file/stdin paths. Commit.
2. **regression-tests** — capture a real fixture from the still-on-
   PATH `cor24-run --assemble --base-addr 0x100 ...` for
   byte-identical regression. Add CLI integration tests in
   `cli/tests/cli.rs` (hex / decimal / `h` suffix accepted, invalid
   exits 2, no flag = default 0 = unchanged output, byte-identical
   regression). One library `.lgo` round-trip test confirming
   non-zero base produces correct L-record addresses.
3. **docs-and-final** — README CLI section gains `--base-addr` row;
   `./scripts/build.sh` end-to-end green; commit; complete --done;
   `dg-mark-pr`.

## Out of scope

- No emulator changes (`cor24-emu`).
- No new output formats.
- No FIXUP record emission (linker concern).
- No removal of `Default::default()` or `Assembler::new()` (additive
  only — library API already supports both call shapes).

## When done

`dg-mark-pr` to rename `feat/cor24-asm-base-addr` →
`pr/cor24-asm-base-addr`. Mike relays via
`dg-relay dcxas sw-cor24-x-assembler pr/cor24-asm-base-addr`. After
relay + reinstall, dcpls flips the two TODO'd `cor24-run --assemble
--base-addr` callsites in their `bootstrap-toolchain` saga.
