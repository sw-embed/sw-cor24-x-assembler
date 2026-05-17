Write `src/examples/assembler/i2c_ssd1306_hello.s`: bit-bang i2c
master that initializes an SSD1306 OLED (addr 0x3C), positions
the GDDRAM pointer at page 0 column 0, writes 25 bytes of font
data spelling "HELLO", and halts.

## Protocol

- 7-bit addr 0x3C → master write byte 0xD0? **No** — 0x3C << 1 = 0x78.
  Use **0x78** as the write byte (R/W = 0).
- Control byte after addr: 0x00 for command stream, 0x40 for data
  stream. Stays in that mode until STOP.
- Per the emulator's lenient-consume, a minimal init suffices:
  `0xAE`, `0x20 0x00`, `0x21 0 127`, `0x22 0 7`, `0xB0`, `0x00`,
  `0x10`, `0xAF`.

## Main flow

```
1. i2cstart
2. i2cwrite(0x78)            ; addr+W
3. i2cwrite(0x00)            ; control: commands
4. i2cwrite(0xAE)            ; display off
5. i2cwrite(0x20)            ; addressing mode setter
6. i2cwrite(0x00)            ;   horizontal
7. i2cwrite(0x21)            ; col range setter
8. i2cwrite(0)               ;   start
9. i2cwrite(127)             ;   end (use lcu since 127 fits signed 7-bit)
10. i2cwrite(0x22)           ; page range setter
11. i2cwrite(0)              ;   start
12. i2cwrite(7)              ;   end
13. i2cwrite(0xB0)           ; page=0
14. i2cwrite(0x00)           ; col low=0
15. i2cwrite(0x10)           ; col high=0
16. i2cwrite(0xAF)           ; display on
17. i2cstop
18. i2cstart
19. i2cwrite(0x78)           ; addr+W
20. i2cwrite(0x40)           ; control: data
21. for each of 25 bytes in hello_data: i2cwrite(byte)
22. i2cstop
23. halt
```

The 25-byte font data lives at the bottom of the file via `.byte`:

```
hello_data:
        .byte 0x7F, 0x08, 0x08, 0x08, 0x7F   ; H
        .byte 0x7F, 0x49, 0x49, 0x49, 0x41   ; E
        .byte 0x7F, 0x40, 0x40, 0x40, 0x40   ; L
        .byte 0x7F, 0x40, 0x40, 0x40, 0x40   ; L
        .byte 0x3E, 0x41, 0x41, 0x41, 0x3E   ; O
hello_end:
```

(Numeric format: COR24 assembler accepts decimal and `Nh` hex.
Convert `0xNN` → `NNh`. For values like `0x7F`, use `7Fh`. For
`0x80+`, prefer `lcu Nh` to avoid sign-extension surprises.)

For the 25-byte write loop, use the existing fp-frame pattern:
push fp + a base pointer + a counter, loop while counter > 0,
load byte via `lb`/`lbu`, call i2cwrite, advance pointer,
decrement counter. Or unroll the loop (25 calls = many lines,
but no register pressure).

The cleaner approach: write a `write_data_block` subroutine that
takes (start_addr, count) — call it once with `la r0, hello_data;
lcu r2, 25`. The subroutine handles the i2cstart/control/loop/
i2cstop.

## Reuse from i2c_ds1307_set.s

Copy verbatim:
- `i2cstart`
- `i2cstop`
- `i2cwrite` (full version with fp-frame addressing — needed for
  the 8-bit MSB-first write)

`i2cread` and uart helpers are NOT needed for this demo.

## Verify

```bash
cargo build --workspace --release
target/release/cor24-asm src/examples/assembler/i2c_ssd1306_hello.s -o /tmp/hello.lgo
EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu
$EMU --lgo /tmp/hello.lgo --i2c-device ssd1306@0x3C --quiet --time 5 -n 50000 2>&1 | tail -5

# The emulator should report a clean halt. To inspect the
# framebuffer content, use --dump-i2c to see the protocol traffic,
# or rely on the unit tests at sw-cor24-emulator/tests/i2c.rs to
# confirm the device wrote the right pixels. The framebuffer
# itself isn't UART-printed by the demo.
```

If `--dump-i2c` is available and the brief recommends it, use
it to verify the protocol traffic matches expectations (init
commands + data writes).

## Register in tests

```rust
(
    "I2C OLED Hello",
    include_str!("../src/examples/assembler/i2c_ssd1306_hello.s"),
),
```

Insert position: between `I2C Add1 Ping` (line 42-45) and
`I2C RTC Read` (currently right after Add1 Ping per dev's state).

The demo halts after one frame; do NOT add to `non_halting`.

## Commit

```
feat(examples): add I2C OLED Hello demo (SSD1306 init + text)

Bit-bang i2c demo: initializes the SSD1306 at 0x3C using the
emulator's lenient-consume init path (display off, horizontal
addressing, full col/page range, pointer at (0,0), display on),
then writes 25 bytes of 5×8 font data for "HELLO" to the data
stream and halts.

Inlines i2cstart / i2cstop / i2cwrite primitives from the prior
ds1307 demos (no .include in this assembler). 4-glyph inline
font table (H, E, L, O) at the bottom; the chr 'L' is reused.

Verified end-to-end via cor24-emu --i2c-device ssd1306@0x3C.

Registered in tests/integration_tests.rs::examples() alphabetically
between "I2C Add1 Ping" and "I2C RTC Read". Halts cleanly.

Refs brief: dcxas-i2c-ssd1306-demos.md (mike, 2026-05-17).
Upstream device: dcemu-i2c-ssd1306-device.md (shipped on
sw-cor24-emulator/main 897fb29).
```

Include `.agentrail/` deltas in the same commit.

## After step 1

`agentrail complete --next-slug i2c-ssd1306-rtc-clock --next-prompt "<step 2 prompt>"`.
Then move to step 2.

Do NOT dg-mark-pr yet — step 2 still to come on the same branch.
