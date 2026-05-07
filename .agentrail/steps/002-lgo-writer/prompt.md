Implement the .lgo writer as a public library module in `src/lgo.rs`.

Public API:

    pub fn write<W: std::io::Write>(
        bytes: &[u8],
        base_addr: u32,
        entry: Option<u32>,
        w: &mut W,
    ) -> std::io::Result<()>

Format spec (read-only reference: `../sw-cor24-emulator/src/loader.rs`):

- Each `L` line: `L<6 hex address><HH HH ...>` — bytes packed at `base_addr` and onward.
- Pack at most 36 data bytes per `L` line (matches existing fixtures `count_down.lgo` and `hello_world.lgo`; keeps line ≤ 79 chars).
- Hex must be UPPERCASE.
- Lines terminated by `\n` (Unix line ending — match existing fixtures).
- If `entry` is `Some(addr)`, append a final `G<6 hex address>` line.
- Empty `bytes` slice: emit no L lines, only G if Some.

Wire it into `src/lib.rs`:

- `pub mod lgo;`
- Re-export `pub use lgo::write as write_lgo;` is OK but not required.

Tests in `src/lgo.rs` `#[cfg(test)] mod tests`:

1. `write_empty_no_entry` — empty input → empty buffer.
2. `write_short_program` — known 6 bytes at addr 0x000000, no entry → produces `L00000080652B0001FF\n`.
3. `write_with_entry` — append `G000093\n`.
4. `write_chunks_at_36_bytes` — 40 bytes → first L has 36 bytes, second L starts at 0x24 with 4 bytes.
5. `roundtrip_through_loader` — feed our output back through `cor24_emulator::loader::load_lgo` into a CpuState and verify bytes/start_addr match.

Verify: `cargo build --workspace`, `cargo clippy --workspace -- -D warnings`, `cargo test --workspace` all green.

Commit with message starting `feat:` and include `.agentrail/` deltas.