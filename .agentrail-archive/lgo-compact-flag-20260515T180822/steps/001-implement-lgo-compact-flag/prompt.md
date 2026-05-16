Implement `--lgo-full` / `--lgo-compact` flag pair in `cor24-asm`
per `dcxas-lgo-compact-flag.md`. Default = Full (today's behavior).

## 1. `src/lgo.rs`

Add a public `LgoMode` enum:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LgoMode {
    /// Emit every L record, including pure-zero blocks. Loadable
    /// in any environment that runs `loadngo`.
    #[default]
    Full,
    /// Omit L records whose entire data payload is `0x00`. Loadable
    /// in `cor24-emu` and on FPGA cold boot only — not safe on warm
    /// reload (relies on the load environment to pre-zero SRAM).
    Compact,
}
```

Thread it through the emitter:

```rust
pub fn write<W: Write>(
    bytes: &[u8],
    base_addr: u32,
    entry: Option<u32>,
    mode: LgoMode,
    w: &mut W,
) -> io::Result<()> {
    for (chunk_idx, chunk) in bytes.chunks(BYTES_PER_LINE).enumerate() {
        if mode == LgoMode::Compact && chunk.iter().all(|&b| b == 0) {
            continue;
        }
        let addr = base_addr + (chunk_idx * BYTES_PER_LINE) as u32;
        write!(w, "L{:06X}", addr)?;
        for b in chunk {
            write!(w, "{:02X}", b)?;
        }
        writeln!(w)?;
    }
    if let Some(addr) = entry {
        writeln!(w, "G{:06X}", addr)?;
    }
    Ok(())
}
```

Update existing tests' `render` helper to take `mode` and pass
`LgoMode::Full` from each existing test (they should all stay
bit-identical).

## 2. `cli/src/main.rs`

Add field to `Cli`:

```rust
lgo_mode: LgoMode,
```

Parse the flag pair (mutually exclusive — track which was set so
both-passed → error):

```rust
"--lgo-full" => {
    if matches!(cli.lgo_mode, LgoMode::Compact) {
        return Err("--lgo-full and --lgo-compact are mutually exclusive".into());
    }
    cli.lgo_mode = LgoMode::Full;
}
"--lgo-compact" => {
    // Need to detect "Full was explicitly set" vs "Full is default".
    // Simplest: track via Option<LgoMode> in Cli, or via a separate
    // bool. Pick whichever fits the existing pattern.
    ...
}
```

Note the default-vs-explicit distinction: `Cli::default()` already
gives `LgoMode::Full`. To detect both-passed, store `Option<LgoMode>`
or add a `bool lgo_mode_explicit` flag — pick whichever matches
the existing parsing style most cleanly.

Pass `cli.lgo_mode` through to all `lgo::write` calls
(`write_lgo_to_path`, `write_lgo_to_stdout`).

Update `USAGE` to list both flags with one-line descriptions, and
add a brief OPTIONS entry.

## 3. Tests

### Unit tests in `src/lgo.rs`

- `compact_skips_pure_zero_chunk` — render `[0; 36]` in Compact;
  output has no `L` line.
- `compact_keeps_partial_zero_chunk` — render `[0,0,0,1,0,0,...]`
  in Compact; emits the L record (not all zero).
- `compact_keeps_g_record` — render with `entry = Some(...)` in
  Compact and zero data; output has only the `G` line.
- `compact_preserves_nonzero_chunks_byte_identical` — for a mixed
  fixture, every non-zero chunk emitted in Full also appears
  byte-identical in Compact's output.
- `full_default_matches_today` — call with `LgoMode::Full` on a
  zero-heavy fixture and assert byte-for-byte against the spelled-out
  expected string (catches accidental default changes).

### CLI integration tests in `cli/tests/cli.rs`

- `lgo_full_default` — assemble a fixture; output matches today's
  output (use the existing `simple.s` or a new one with zero
  regions).
- `lgo_compact_strips_zero_lines` — fixture with `.zero N` to
  guarantee zero-only chunks; assert no `^L[0-9A-F]{6}0+$` lines
  in `--lgo-compact` output.
- `lgo_full_and_compact_mutex` — both flags → exit 2 with stderr
  mentioning both flag names.
- `lgo_compact_smaller_than_full` — fixture with substantial zero
  fill; compact output strictly fewer bytes than full output.

### Round-trip in `tests/integration_tests.rs`

- `lgo_full_and_compact_load_identically` — assemble a small
  fixture twice (Full and Compact), load each via `load_lgo` into
  fresh `CpuState`, verify the resulting memory image is identical
  at the addresses written by Full (Compact's CpuState defaults
  the rest to zero, which matches Full's explicit zero writes).

## 4. README.md

Add the two flags to the CLI example block (after `--base-addr`):

```bash
cor24-asm prog.s --lgo-compact -o out.lgo  # omit pure-zero L records (cor24-emu / cold-boot only)
```

And one-line note in the OPTIONS-equivalent prose: default is full;
compact loads only in `cor24-emu` and on FPGA cold boot.

## 5. Verify

```bash
cargo build --workspace --release
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
target/release/cor24-asm -V
```

Spot-check by hand:

```bash
# zero-heavy fixture
echo -e '.byte 1,2,3\n.zero 64\n.byte 9' > /tmp/zh.s
target/release/cor24-asm /tmp/zh.s -o /tmp/full.lgo
target/release/cor24-asm /tmp/zh.s --lgo-compact -o /tmp/compact.lgo
ls -la /tmp/full.lgo /tmp/compact.lgo  # compact strictly smaller
```

## 6. Commit

```
feat: add --lgo-full / --lgo-compact flag pair

Default --lgo-full preserves today's bit-identical output (every L
record emitted, including pure-zero blocks) — hardware-safe in any
environment that runs the makerlisp loadngo loader. --lgo-compact
opts in to omitting pure-zero L records; output loads correctly in
cor24-emu (always) and on FPGA cold boot, but not on warm reload.

Mutually exclusive flags. No format changes (compact .lgo is a
strict subset of full .lgo). G records and non-zero L records
unchanged in both modes.

Refs brief: dcxas-lgo-compact-flag.md
```

## 7. Wrap

`agentrail complete --done`. `dg-mark-pr` →
`pr/lgo-compact-flag`. Then post-complete bookkeeping on a
separate branch → `pr/lgo-compact-flag-saga-complete`. STOP.
