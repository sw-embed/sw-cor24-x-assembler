Implement the .lst (listing) writer as a public library module in `src/listing.rs` matching the existing emulator emitter byte-for-byte.

Reference: `../sw-cor24-emulator/cli/src/run.rs:1602-1617`

    for line in &result.lines {
        if !line.bytes.is_empty() {
            let bytes: String = line.bytes.iter().map(|b| format!("{:02X} ", b)).collect();
            writeln!(lst_file, "{:04X}: {:14} {}", line.address, bytes.trim(), line.source).ok();
        } else if !line.source.is_empty() {
            writeln!(lst_file, "                    {}", line.source).ok();
        }
    }

Note the deliberate column quirk: the bytes branch puts source at col 21 (4+2+14+1); the source-only branch uses 20 spaces. Reproduce verbatim — downstream parsers may rely on this.

Public API:

    pub fn write<W: std::io::Write>(
        result: &crate::AssemblyResult,
        w: &mut W,
    ) -> std::io::Result<()>

Wire it into `src/lib.rs`:

- `pub mod listing;`

Tests in `#[cfg(test)] mod tests`:

1. `empty_result_writes_nothing` — fresh AssemblyResult { bytes: [], lines: [], errors: [], labels: {} } → empty buffer.
2. `bytes_line_format` — synthesize an AssembledLine { address: 0x10, bytes: [0x80, 0x65], source: "  push fp" } → exactly `0010: 80 65          push fp\n` (14-wide bytes column).
3. `source_only_line_format` — AssembledLine with empty bytes, non-empty source `"halt:"` → exactly `                    halt:\n` (20 spaces).
4. `mixed_lines` — feed two lines (one with bytes, one source-only) and verify both get written in order with correct column layout.
5. `roundtrip_via_assembler` — assemble a small `.s` source string with the real Assembler (`Assembler::new().assemble("lc r0,42\nhalt:\nbra halt")`), pass the result to `listing::write`, and assert the output is non-empty and contains "halt:" on a source-only line.

Reproduce the column quirk verbatim — do NOT normalize.

Verify: `cargo build --workspace`, `cargo clippy --workspace -- -D warnings`, `cargo test --workspace` all green.

Commit with `feat:` prefix and include `.agentrail/` deltas.