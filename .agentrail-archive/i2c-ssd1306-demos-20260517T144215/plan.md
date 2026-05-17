# Saga: i2c-ssd1306-demos

## Goal

Add two SSD1306 OLED display demos to `src/examples/assembler/`:

- **`i2c_ssd1306_hello.s`** — minimal "init then write HELLO"
  text-rendering demo. Halts after one frame.
- **`i2c_ssd1306_rtc_clock.s`** — combines DS1307 read + SSD1306
  draw to render `HH:MM:SS` continuously, redrawn periodically.
  Loops forever (`non_halting`).

Per mike's brief `dcxas-i2c-ssd1306-demos.md`.

## Cross-repo position

Middle of the three-agent SSD1306 thread:

- Upstream (shipped): `dcemu-i2c-ssd1306-device.md` — emulator
  `Ssd1306Device` now on origin/main (897fb29) / origin/dev
  (835d9b6). Sibling clone refreshed and verified.
- Downstream (waiting on us): `dwxas-i2c-ssd1306-panel.md` —
  web panel + dropdown entries `I2C OLED Hello` / `I2C OLED RTC
  Clock`.

## What's actually changing

| File | Change |
|---|---|
| `src/examples/assembler/i2c_ssd1306_hello.s` (new) | init sequence + write 25 bytes of "HELLO" font data + halt |
| `src/examples/assembler/i2c_ssd1306_rtc_clock.s` (new) | combined DS1307 read + SSD1306 draw loop; HH:MM:SS redrawn periodically |
| `tests/integration_tests.rs` (2 hunks) | register `("I2C OLED Hello", ...)` and `("I2C OLED RTC Clock", ...)` between `I2C Add1 Ping` and `I2C RTC Read`; add `"I2C OLED RTC Clock"` to `non_halting` |

No public-API changes, no Cargo.toml changes.

## SSD1306 contract recap (per emulator's `ssd1306.rs`)

- 7-bit addr `0x3C` default → master write byte `0x78`.
- Control byte after START+address: `0x00` = command stream;
  `0x40` = data stream. Rest of transaction stays in that mode
  until STOP. (`Co=1` variants exist but standard drivers don't
  use them.)
- Commands modeled semantically: `0xAE` off / `0xAF` on, `0x20
  mode` (0=horiz/1=vert/2=page), `0x21 col_start col_end`, `0x22
  page_start page_end`, `0xB0..0xB7` page pointer, `0x00..0x0F`
  col-low nibble, `0x10..0x1F` col-high nibble. Other init-
  sequence opcodes (contrast, clock divide, multiplex, COM pins,
  charge pump) are lenient-consumed: param count honored, no
  state effect. Lets us skip the full real-driver init.
- GDDRAM layout: `framebuffer[page * 128 + col]` = 8 vertical
  pixels of that column, **LSB at top**. Font bytes flow directly.
- Default reset: framebuffer zero, display off, addressing mode
  Page, pointer (0, 0).

Minimal init sufficient for the lenient device:
- `0xAE` (display off — clean start)
- `0x20, 0x00` (horizontal addressing — pointer auto-increments
  through col range, wraps to next page)
- `0x21, 0, 127` (col range)
- `0x22, 0, 7` (page range)
- `0xB0` (page = 0)
- `0x00` (col-low = 0)
- `0x10` (col-high = 0)
- `0xAF` (display on)

## Architectural notes

- Each demo inlines its own i2c bit-bang primitives (`i2cstart` /
  `i2cstop` / `i2cwrite`) copied verbatim from the DS1307 demos.
  `i2cread` only needed in the clock demo. No `.include` in this
  assembler.
- Font tables inlined per demo per brief recommendation (extract
  to `lib/font5x8.s` when a 3rd demo arrives).
  - Hello demo: H, E, L, O = 4 glyphs × 5 bytes = 20 bytes.
  - Clock demo: 0-9, ':' = 11 glyphs × 5 bytes = 55 bytes.
- Glyph encoding: 5 bytes per char, each byte = one column, LSB
  at top, MSB unused for the 5×7 effective glyph in an 8-tall
  page. Bytes flow byte-for-byte to GDDRAM.
- Hello demo: single i2c-data-stream write of 25 bytes (5 chars
  × 5 cols). Horizontal addressing auto-advances column.
- Clock demo:
  - Init once.
  - Loop: read DS1307 (H/M/S registers), reposition pointer to
    (0, 0), write 8 BCD-derived glyphs ("HH:MM:SS" = 2 digits +
    colon + 2 digits + colon + 2 digits) = 8 × 5 = 40 bytes,
    spin a delay loop, repeat.
  - Delay between updates: pick a value that's responsive in
    web at 100k IPS budget. ~10k spin iterations between reads
    feels right (~100ms at 100k IPS). Tune empirically.

## Out of scope

- No shared `lib/font5x8.s` file (brief recommends inline for 2
  demos; extract when 3rd arrives).
- No scrolling, animation, multi-line, multi-font.
- No SSD1306 driver crate or library abstraction.
- No `src/` library or CLI changes.
- No web panel work (dwxas's downstream saga).

## Steps

1. **i2c-ssd1306-hello** — write `i2c_ssd1306_hello.s` + tests
   entry. Verify "HELLO" appears in the framebuffer end-to-end
   via `cor24-emu --i2c-device ssd1306@0x3C`. Commit.
2. **i2c-ssd1306-rtc-clock** — write `i2c_ssd1306_rtc_clock.s`
   + tests entries (registered + non_halting). Verify two-device
   end-to-end via
   `cor24-emu --i2c-device 'ds1307@0x68?preset=system'
                --i2c-device ssd1306@0x3C`. Commit.

## When done

Single `pr/i2c-ssd1306-demos` branch with both work commits.
Then `pr/i2c-ssd1306-demos-saga-complete` as a strict superset
per the Part 2 discipline.
