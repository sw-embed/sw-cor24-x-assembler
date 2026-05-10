//! `.lgo` writer — emits the MakerLisp "load and go" text format consumed
//! by `cor24-emu --lgo` and parsed by `cor24_emulator::loader`.
//!
//! Format (mirrors the reader at `cor24_emulator::loader`):
//!
//! - `L<AAAAAA><HH>...` — load hex bytes at the given 24-bit address.
//! - `G<AAAAAA>` — set PC to address (optional; emitted only when `entry`
//!   is `Some`).
//!
//! Up to 36 data bytes are packed per `L` line, matching the historical
//! convention of the existing fixtures (`hello_world.lgo`,
//! `count_down.lgo`) and keeping every line within an 80-column terminal.
//! Hex is uppercase. Lines are terminated with `\n`.
//!
//! Empty input produces no output unless `entry` is `Some`, in which
//! case only a `G` line is written.

use std::io::{self, Write};

const BYTES_PER_LINE: usize = 36;

/// Selects how the writer treats `L` records whose data is entirely
/// zero. Default is [`LgoMode::Full`], which preserves today's
/// bit-identical output and is loadable in any environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LgoMode {
    /// Emit every `L` record, including pure-zero blocks. Loadable
    /// in any environment that runs makerlisp's `loadngo`.
    #[default]
    Full,
    /// Omit `L` records whose entire data payload is `0x00`.
    /// Loadable in `cor24-emu` (always — fresh OS process zero) and
    /// on FPGA cold boot (BRAM zero from bitstream config). NOT
    /// safe on warm reload, where stale SRAM contents would survive.
    Compact,
}

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

#[cfg(test)]
mod tests {
    use super::*;
    use cor24_emulator::cpu::state::CpuState;
    use cor24_emulator::loader::load_lgo;

    fn render(bytes: &[u8], base_addr: u32, entry: Option<u32>) -> String {
        render_mode(bytes, base_addr, entry, LgoMode::Full)
    }

    fn render_mode(bytes: &[u8], base_addr: u32, entry: Option<u32>, mode: LgoMode) -> String {
        let mut buf = Vec::new();
        write(bytes, base_addr, entry, mode, &mut buf).unwrap();
        String::from_utf8(buf).unwrap()
    }

    #[test]
    fn write_empty_no_entry() {
        assert_eq!(render(&[], 0, None), "");
    }

    #[test]
    fn write_empty_with_entry() {
        assert_eq!(render(&[], 0, Some(0x000093)), "G000093\n");
    }

    #[test]
    fn write_short_program() {
        let bytes = [0x80, 0x65, 0x2B, 0x00, 0x01, 0xFF];
        assert_eq!(render(&bytes, 0, None), "L00000080652B0001FF\n");
    }

    #[test]
    fn write_with_entry() {
        let bytes = [0x80];
        assert_eq!(render(&bytes, 0, Some(0x000093)), "L00000080\nG000093\n");
    }

    #[test]
    fn write_chunks_at_36_bytes() {
        let bytes: Vec<u8> = (0..40u8).collect();
        let out = render(&bytes, 0, None);
        let mut lines = out.lines();
        let l1 = lines.next().unwrap();
        let l2 = lines.next().unwrap();
        assert!(lines.next().is_none());

        assert!(l1.starts_with("L000000"));
        assert_eq!(l1.len(), 1 + 6 + BYTES_PER_LINE * 2);

        // Second line continues at 0x24 (36) with 4 bytes.
        assert_eq!(&l2[..7], "L000024");
        assert_eq!(l2.len(), 1 + 6 + 4 * 2);
    }

    #[test]
    fn write_uses_uppercase_hex() {
        let out = render(&[0xab, 0xcd, 0xef], 0xfedcba, None);
        assert_eq!(out, "LFEDCBAABCDEF\n");
    }

    #[test]
    fn roundtrip_through_loader_no_entry() {
        let original: Vec<u8> = (0..100u8).map(|i| i.wrapping_mul(7)).collect();
        let out = render(&original, 0x000010, None);

        let mut cpu = CpuState::new();
        let result = load_lgo(&out, &mut cpu).unwrap();

        assert_eq!(result.bytes_loaded, original.len());
        assert_eq!(result.start_addr, None);
        for (i, &b) in original.iter().enumerate() {
            assert_eq!(cpu.read_byte(0x000010 + i as u32), b);
        }
    }

    #[test]
    fn write_high_base_addr_chunks_correctly() {
        // 50 bytes at base 0x010000 → first L at 0x010000 (36 bytes), second
        // L at 0x010024 (14 bytes). Exercises 6-hex addressing past 0xFFFF.
        let bytes: Vec<u8> = (0..50u8).collect();
        let out = render(&bytes, 0x010000, None);
        let mut lines = out.lines();
        let l1 = lines.next().unwrap();
        let l2 = lines.next().unwrap();
        assert!(lines.next().is_none());

        assert!(l1.starts_with("L010000"), "first line: {}", l1);
        assert!(l2.starts_with("L010024"), "second line: {}", l2);
    }

    #[test]
    fn roundtrip_through_loader_with_entry() {
        let original = [0x80, 0x65, 0x2B];
        let out = render(&original, 0x000000, Some(0x000093));

        let mut cpu = CpuState::new();
        let result = load_lgo(&out, &mut cpu).unwrap();

        assert_eq!(result.bytes_loaded, original.len());
        assert_eq!(result.start_addr, Some(0x000093));
    }

    // --- LgoMode::Compact tests ---

    #[test]
    fn compact_skips_pure_zero_chunk() {
        let bytes = vec![0u8; 36];
        let out = render_mode(&bytes, 0, None, LgoMode::Compact);
        assert_eq!(out, "");
    }

    #[test]
    fn compact_skips_only_zero_chunks_in_mixed_input() {
        // 3 chunks of 36 bytes: chunk 0 zero, chunk 1 non-zero, chunk 2 zero.
        let mut bytes = vec![0u8; 36 * 3];
        bytes[36 + 5] = 0xAB;
        let out = render_mode(&bytes, 0, None, LgoMode::Compact);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 1, "expected 1 line, got: {:?}", lines);
        assert!(lines[0].starts_with("L000024"), "addr should be 36 (0x24): {}", lines[0]);
    }

    #[test]
    fn compact_keeps_partial_zero_chunk() {
        // Chunk has zeros around a single non-zero byte — must still emit.
        let mut bytes = vec![0u8; 36];
        bytes[10] = 0x42;
        let out = render_mode(&bytes, 0, None, LgoMode::Compact);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].starts_with("L000000"));
        assert!(lines[0].contains("42"));
    }

    #[test]
    fn compact_keeps_g_record_when_data_all_zero() {
        let bytes = vec![0u8; 36];
        let out = render_mode(&bytes, 0, Some(0x000100), LgoMode::Compact);
        assert_eq!(out, "G000100\n");
    }

    #[test]
    fn compact_keeps_g_record_with_mixed_data() {
        let bytes = [0x80, 0x65];
        let out = render_mode(&bytes, 0, Some(0x000093), LgoMode::Compact);
        assert_eq!(out, "L0000008065\nG000093\n");
    }

    #[test]
    fn compact_preserves_nonzero_lines_byte_identical_to_full() {
        // Mixed fixture: [non-zero chunk, zero chunk, non-zero chunk].
        let mut bytes = vec![0u8; 36 * 3];
        for (i, b) in bytes.iter_mut().take(36).enumerate() {
            *b = (i + 1) as u8;
        }
        for (i, b) in bytes.iter_mut().skip(72).take(36).enumerate() {
            *b = (i + 100) as u8;
        }
        let full = render_mode(&bytes, 0, None, LgoMode::Full);
        let compact = render_mode(&bytes, 0, None, LgoMode::Compact);
        let full_nonzero: Vec<&str> = full.lines().filter(|l| !is_pure_zero_l_line(l)).collect();
        let compact_lines: Vec<&str> = compact.lines().collect();
        assert_eq!(full_nonzero, compact_lines);
    }

    fn is_pure_zero_l_line(line: &str) -> bool {
        if !line.starts_with('L') || line.len() < 8 {
            return false;
        }
        line[7..].chars().all(|c| c == '0')
    }

    #[test]
    fn compact_round_trips_through_loader() {
        // Compact-emitted .lgo loads identically into a fresh CpuState
        // (which starts zeroed) — the omitted zero L records are
        // implicit because the loader doesn't pre-clear and CpuState
        // defaults to zero.
        let mut bytes = vec![0u8; 36 * 4];
        bytes[5] = 0x11;
        bytes[36 + 10] = 0; // chunk 1 stays all-zero → omitted in compact
        bytes[72] = 0xAB;
        bytes[108 + 35] = 0xCD;

        let full = render_mode(&bytes, 0, None, LgoMode::Full);
        let compact = render_mode(&bytes, 0, None, LgoMode::Compact);

        let mut cpu_full = CpuState::new();
        let mut cpu_compact = CpuState::new();
        load_lgo(&full, &mut cpu_full).unwrap();
        load_lgo(&compact, &mut cpu_compact).unwrap();

        for addr in 0..bytes.len() as u32 {
            assert_eq!(
                cpu_full.read_byte(addr),
                cpu_compact.read_byte(addr),
                "byte mismatch at {:06X}", addr
            );
        }
    }

    #[test]
    fn full_default_unchanged_for_zero_heavy_input() {
        // Catches accidental default flips: a zero-heavy fixture under
        // the default mode must emit explicit zero L records.
        let bytes = vec![0u8; 36];
        let out = render(&bytes, 0, None);
        assert_eq!(out, format!("L000000{}\n", "00".repeat(36)));
    }
}
