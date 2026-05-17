Write `src/examples/assembler/i2c_ssd1306_rtc_clock.s`: combines
the DS1307 RTC read pattern from `i2c_ds1307_read.s` with the
SSD1306 init+write pattern from `i2c_ssd1306_hello.s` to render
`HH:MM:SS` at the top of the OLED, redrawn periodically.
Loops forever.

## Main flow

```
1. init stack
2. SSD1306 init burst (same 8 commands as the hello demo)
3. Loop forever:
   a. DS1307 read: i2cstart → write 0xD0 → write 0x00 (pointer)
      → restart → write 0xD1 → read S, M, H → i2cstop
   b. Mask S with 0x7F, H with 0x3F (drop CH and 12/24 bits)
   c. Reposition SSD1306 pointer to (0, 0): i2cstart → write
      0x78 → write 0x00 (control: commands) → write 0xB0 (page=0)
      → write 0x00 (col low) → write 0x10 (col high) → i2cstop
   d. Render 8 glyphs (40 bytes total) in one data burst:
      i2cstart → write 0x78 → write 0x40 (control: data) →
      write H's tens digit (5 font bytes) → write H's ones digit
      → write ':' → write M's tens → write M's ones → write ':'
      → write S's tens → write S's ones → i2cstop
   e. Delay loop (~10k spin iterations between updates)
4. (never reached) halt
```

## Digit-to-glyph mapping

BCD nibble (0-9) → font row offset:

```
digit_font:
        ; ... 0..9, 5 bytes each = 50 bytes ...
        .byte 3Eh, 51h, 49h, 45h, 3Eh   ; 0
        .byte 00h, 42h, 7Fh, 40h, 00h   ; 1
        ; ... etc
colon_font:
        .byte 00h, 36h, 36h, 00h, 00h   ; :
```

Full 0-9 font glyphs (LSB-at-top column encoding, standard 5x7):

```
0: 3Eh, 51h, 49h, 45h, 3Eh
1: 00h, 42h, 7Fh, 40h, 00h
2: 42h, 61h, 51h, 49h, 46h
3: 21h, 41h, 45h, 4Bh, 31h
4: 18h, 14h, 12h, 7Fh, 10h
5: 27h, 45h, 45h, 45h, 39h
6: 3Ch, 4Ah, 49h, 49h, 30h
7: 01h, 71h, 09h, 05h, 03h
8: 36h, 49h, 49h, 49h, 36h
9: 06h, 49h, 49h, 29h, 1Eh
```

(Standard 5x7 glyph encoding matching the Picaxe / Adafruit
micro font set. MSB unused for 7-row in 8-bit page.)

To get a glyph address for digit n (0-9):
```
glyph_addr = digit_font + n * 5
```

Use `mul r0, r2` (n in r0, 5 in r2) for the multiply, then add
the base.

## render_digit(r0 = digit 0-9) subroutine

Writes 5 font bytes for the given digit through the OPEN i2c
data transaction (caller must have already done i2cstart + 0x78
+ 0x40 and will i2cstop afterwards). Computes the font address
and writes 5 bytes.

```
render_digit:
        push    r1
        ; r0 = digit; compute addr = digit_font + digit * 5
        lc      r2, 5
        mul     r0, r2          ; r0 = digit * 5
        la      r2, digit_font
        add     r0, r2          ; r0 = font addr
        push    fp
        push    r0              ; ptr at 0(fp)
        mov     fp, sp
        lc      r2, 5           ; counter
.rd_loop:
        lw      r1, 0(fp)       ; current ptr
        lbu     r0, 0(r1)       ; byte
        push    r2
        la      r1, .rd_ret
        la      r2, i2cwrite
        jal     r1, (r2)
.rd_ret:
        pop     r2
        lw      r0, 0(fp)
        add     r0, 1
        sw      r0, 0(fp)
        add     r2, -1
        ceq     r2, z
        brf     .rd_loop
        mov     sp, fp
        add     sp, 3
        pop     fp
        pop     r1
        jmp     (r1)
```

## render_colon: writes 5 bytes of the ':' glyph

Same shape as render_digit but with a fixed pointer to
colon_font.

## render_bcd_byte(r0 = BCD byte): writes 10 font bytes (2 digits)

```
render_bcd_byte:
        push    r1
        push    r0
        ; high nibble
        lc      r1, 4
        srl     r0, r1
        la      r1, .rbb_r1
        la      r2, render_digit
        jal     r1, (r2)
.rbb_r1:
        pop     r0
        ; low nibble
        lcu     r2, 0Fh
        and     r0, r2
        la      r1, .rbb_r2
        la      r2, render_digit
        jal     r1, (r2)
.rbb_r2:
        pop     r1
        jmp     (r1)
```

## Delay loop (between RTC reads)

```
delay:
        push    r1
        la      r0, 10000      ; iterations (tunable; ~10k feels right)
.dl_loop:
        ceq     r0, z
        brt     .dl_done
        add     r0, -1
        bra     .dl_loop
.dl_done:
        pop     r1
        jmp     (r1)
```

## Reuse from existing demos

Copy verbatim:
- `i2cstart`, `i2cstop`, `i2cwrite`, `i2cread` (from
  `i2c_ds1307_read.s`)
- The SSD1306 init burst structure (8 commands) from
  `i2c_ssd1306_hello.s`

## Verify

```bash
target/release/cor24-asm src/examples/assembler/i2c_ssd1306_rtc_clock.s -o /tmp/dcxas_clock.lgo
EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu

# Two-device: RTC at host time + OLED
$EMU --lgo /tmp/dcxas_clock.lgo \
     --i2c-device 'ds1307@0x68?preset=system' \
     --i2c-device ssd1306@0x3C \
     --quiet --time 3 -n 500000 --dump-i2c 2>&1 | tail -50

# Expect: init burst once, then alternating RTC-read and
# OLED-draw bursts. Clean STOPs between transactions.

# Also try without RTC (DS1307 read returns 0xFF → garbage
# digit, but should still loop without crashing):
$EMU --lgo /tmp/dcxas_clock.lgo \
     --i2c-device ssd1306@0x3C \
     --quiet --time 2 -n 200000 2>&1 | tail -3
```

## Register in tests

```rust
(
    "I2C OLED RTC Clock",
    include_str!("../src/examples/assembler/i2c_ssd1306_rtc_clock.s"),
),
```

Insert position: between "I2C OLED Hello" and "I2C RTC Read"
(alphabetically).

Add `"I2C OLED RTC Clock"` to the `non_halting` array (loops
forever by design).

## Commit

```
feat(examples): add I2C OLED RTC Clock demo (SSD1306 + DS1307)

Two-device i2c demo: initializes the SSD1306, then loops
forever reading the DS1307 time registers and rendering
"HH:MM:SS" at page 0 column 0 of the OLED. Redraws every ~10k
spin iterations (responsive at the web demo's 100k IPS budget).

Combines the bit-bang i2c primitives + DS1307 read pattern from
i2c_ds1307_read.s with the SSD1306 init pattern from
i2c_ssd1306_hello.s. Adds an inline 10-glyph digit font (0-9)
plus the ':' separator (55 bytes total) and a render_digit
subroutine that computes glyph_addr = digit_font + n*5 and
writes 5 font bytes through the open i2c data transaction.

Verified end-to-end via cor24-emu with both devices attached
(--i2c-device 'ds1307@0x68?preset=system' --i2c-device
ssd1306@0x3C): alternating RTC-read and OLED-draw bursts, host
time reflected on the display.

Registered in tests/integration_tests.rs::examples() alphabetically
between "I2C OLED Hello" and "I2C RTC Read", and added to
non_halting (loops forever by design).

Refs brief: dcxas-i2c-ssd1306-demos.md (mike, 2026-05-17).
```

## Wrap

`agentrail complete --done`. `dg-mark-pr` → `pr/i2c-ssd1306-demos`.
Then `feat/i2c-ssd1306-demos-saga-complete` off pr/, commit
bookkeeping, `dg-mark-pr` → `pr/i2c-ssd1306-demos-saga-complete`
(strict superset per Part 2 discipline).
