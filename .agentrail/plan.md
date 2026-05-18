# Saga: spi-sdcard-and-nor-flash-demos

## Goal

Add two SPI device demos to `src/examples/assembler/`:

- **`spi_sdcard_read.s`** — SD-SPI init handshake (CMD0/CMD8/CMD55+
  ACMD41/CMD16/CMD17), read sector 0 (512 bytes + 2 CRC), print
  first 16 bytes to UART as hex pairs separated by spaces +
  newline. Halts.
- **`spi_nor_flash_demo.s`** — W25Q32 full read-erase-program-read
  cycle: JEDEC ID, read 4 bytes before, write-enable + sector
  erase, poll WIP, write-enable + page program (0xDE 0xAD 0xBE
  0xEF), poll WIP, read 4 bytes after. Prints `JEDEC: EF 40 16`,
  `BEFORE: XX XX XX XX`, `AFTER: DE AD BE EF`. Halts.

Per mike's brief `dcxas-spi-sdcard-and-nor-flash-demos.md`.

## Cross-repo position

Middle of a three-agent thread:

- Upstream (shipped): `dcemu-spi-sdcard-and-nor-flash.md` —
  emulator `SdCardDevice` + `W25q32Device` are on
  `sw-cor24-emulator/main` (Release c4ddb55 / dev 5002c0d).
  Sibling clone refreshed, devices verified present
  (`src/peripherals/spi/devices/{sdcard,w25q32}.rs`).
- Downstream (waiting on us): `dwxas-spi-sdcard-and-nor-flash-panels.md`
  — web panels + dropdown entries.

## SPI MMIO contract (per `sw-cor24-emulator/src/cpu/state.rs:45-51`)

- `0xFF0030` SPI_DATA — write = MOSI bit (bit 0 = next bit shifted
  out); read = last sampled MISO bit (bit 0).
- `0xFF0031` SPI_SCLK — bit 0 drives SCLK level.
- `0xFF0032` SPI_SELN — bit 0 drives SELN (active-low CS; 1 = idle/
  deselected, 0 = selected). Currently single-slave; the
  `@cs=<n>` registry param is parsed and stored for observation
  but not yet enforced (multi-slave is plan §9 future work). For
  these demos the single SELN line addresses whichever device is
  attached.

Mode 0 (CPOL=0, CPHA=0): master sets MOSI on SCLK falling edge,
slave drives MISO on SCLK falling edge; sample both on SCLK rising.

## SPI primitives needed

- `cs_low` / `cs_high` — write SELN = 0 / 1.
- `spi_xchg_byte(r0 = MOSI byte) → r0 = MISO byte` — 8 bit-clocks
  MSB-first; per bit: write MOSI, pulse SCLK 1→0, sample MISO,
  assemble.

For SD card (Step 1, additional helpers):

- `sd_send_cmd(opcode | 0x40, arg32, crc) → r0 = R1` — push 6 bytes,
  poll R1 (loop while MISO byte's bit 7 is set).
- `sd_wait_token` — poll for `0xFE` data start token.

For NOR flash (Step 2, mostly inline):

- `nor_read_status` — opcode `0x05` then read 1 byte; loop on
  WIP bit (bit 0).
- `nor_write_enable` — opcode `0x06` (1-byte command).
- `nor_sector_erase(addr24)` — opcode `0x20` + 3 addr bytes.
- `nor_page_program(addr24, data[])` — opcode `0x02` + 3 addr +
  data bytes.

Each demo inlines its own primitives — no `.include` mechanism.

## Print helpers

Reused across both demos (each inlines its own copy):
- `putc` (UART write with TX-busy poll) — copied from prior demos.
- `print_hex_nibble` — copied from prior demos.
- `print_hex_byte` — calls print_hex_nibble × 2 for high/low.
- `print_hex_space_byte` — print_hex_byte + ' '.

## What's actually changing

| File | Change |
|---|---|
| `src/examples/assembler/spi_sdcard_read.s` (new) | SD init + sector 0 read + first-16-bytes hex print |
| `src/examples/assembler/spi_nor_flash_demo.s` (new) | W25Q32 JEDEC + read + erase + program + read cycle |
| `tests/integration_tests.rs` (2 hunks per step) | register both in `examples()` alphabetically; integration tests with fixture sdcard image; both halt cleanly |
| `tests/programs/sdcard-test.img` (new) | 512-byte fixture with bytes `0x00..0x1F` repeated for sector-0 read assertion |

## Out of scope (per brief)

- No FAT filesystem code; sector 0 is raw bytes.
- No multi-sector reads (CMD18).
- No 4 KB page program; 4-byte program is enough.
- No write-protection / status reg 2/3 demos.

## Steps

1. **spi-sdcard-read** — `spi_sdcard_read.s` + fixture + test;
   commit.
2. **spi-nor-flash-demo** — `spi_nor_flash_demo.s` + test;
   commit.

## When done

Two pr/ branches:
- `pr/spi-sdcard-and-nor-flash-demos` (2 work commits)
- `pr/spi-sdcard-and-nor-flash-demos-saga-complete` (strict
  superset = work + 1 bookkeeping commit)
