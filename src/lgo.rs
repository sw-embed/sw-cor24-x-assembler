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

pub fn write<W: Write>(
    bytes: &[u8],
    base_addr: u32,
    entry: Option<u32>,
    w: &mut W,
) -> io::Result<()> {
    for (chunk_idx, chunk) in bytes.chunks(BYTES_PER_LINE).enumerate() {
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
        let mut buf = Vec::new();
        write(bytes, base_addr, entry, &mut buf).unwrap();
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
}
