Fix `src/examples/assembler/i2c_ssd1306_rtc_clock.s` per
`dcxas-fix-i2c-ssd1306-rtc-clock-read.md`. Root cause analyzed
in the saga plan: master-ACK on the last byte keeps the slave
pulling SDA low (`slave_sda_pull = true`), so `i2cstop`'s SDA-up
write is suppressed by the wired-AND, STOP is never detected,
and the bus state machine stays in the read transaction.

## The fix

Add an `i2creadnak` subroutine — copy of `i2cread` but with
master-NAK at the end instead of master-ACK:

```asm
i2creadnak:
        push    r1
        push    fp
        lc      r0, 0
        push    r0              ; acc at 0(fp)
        mov     fp, sp
        lcu     r2, 8           ; counter (8 bits to read)
.irn_loop:
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1 (release for slave)
        sb      r0, 0(r1)       ; SCL = 1 (slave puts bit on line)
        lbu     r0, 1(r1)       ; r0 = bit
        push    r0              ; save bit
        lw      r0, 0(fp)       ; current acc
        add     r0, r0          ; shift left
        pop     r1              ; bit into r1
        or      r0, r1
        sw      r0, 0(fp)       ; updated acc
        la      r1, -65504
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0
        add     r2, -1
        ceq     r2, z
        brf     .irn_loop
        ; --- master NAK (release SDA on 9th clock — slave then releases too) ---
        la      r1, -65504
        lcu     r0, 1
        sb      r0, 1(r1)       ; SDA = 1 (release — NAK)
        sb      r0, 0(r1)       ; SCL = 1 (slave samples NAK)
        lc      r0, 0
        sb      r0, 0(r1)       ; SCL = 0
        ; teardown
        pop     r0              ; r0 = acc (return value)
        pop     fp
        pop     r1
        jmp     (r1)
```

Then in `main_loop`, change the 3rd read (for H) to use
`i2creadnak` instead of `i2cread`. The two earlier reads (S, M)
keep using `i2cread` because the slave SHOULD continue
streaming after them.

Find the change site:

```asm
.rl_rrm:
        push    r0              ; M at sp+0; S at sp+3
        la      r1, .rl_rrh
        la      r2, i2cread        ; ← CHANGE TO i2creadnak
        jal     r1, (r2)
.rl_rrh:
        push    r0              ; H at sp+0; M at sp+3; S at sp+6
```

becomes:

```asm
        la      r2, i2creadnak     ; NAK on last byte so i2cstop can fire STOP
```

That's the only call-site change. The S and M reads continue
to use the unchanged `i2cread`.

## Verify

```bash
# Reproduce the bug pre-fix (just to confirm we're seeing the right thing):
git stash   # temporarily stash fix
target/release/cor24-asm src/examples/assembler/i2c_ssd1306_rtc_clock.s -o /tmp/c_pre.lgo
git stash pop  # restore fix
target/release/cor24-asm src/examples/assembler/i2c_ssd1306_rtc_clock.s -o /tmp/c_post.lgo

EMU=/disk1/.../sw-cor24-emulator/target/release/cor24-emu

# Pre-fix: should show 17+ RDs without STOP
$EMU --lgo /tmp/c_pre.lgo --i2c-device ds1307@0x68 --i2c-device ssd1306@0x3C \
     --time 0.05 --speed 100000 --dump-i2c | grep -cE 'RD   0x68'
# expect: 17+

# Post-fix: should show exactly 3 RDs per iteration
$EMU --lgo /tmp/c_post.lgo --i2c-device ds1307@0x68 --i2c-device ssd1306@0x3C \
     --time 0.05 --speed 100000 --dump-i2c | grep -E 'STOP|RD   0x68'
# expect: 3 RDs followed by STOP, repeating

# With a real time:
$EMU --lgo /tmp/c_post.lgo \
     --i2c-device 'ds1307@0x68?hour=12&minute=34&second=56' \
     --i2c-device ssd1306@0x3C \
     --time 0.1 --speed 100000 --dump-i2c | grep "WR   0x3C" | head -50
# expect: OLED data bytes decode to "12:34:56" glyphs (10 bytes per digit pair
# + 5 per colon = 40 bytes per frame).
```

Regression check the other demos:

```bash
target/release/cor24-asm src/examples/assembler/i2c_ssd1306_hello.s -o /tmp/h.lgo
$EMU --lgo /tmp/h.lgo --i2c-device ssd1306@0x3C --quiet --time 5 -n 100000 \
     | grep -c "Executed"
# expect: clean halt in ~6500 instructions

target/release/cor24-asm src/examples/assembler/i2c_ds1307_read.s -o /tmp/r.lgo
$EMU --lgo /tmp/r.lgo --i2c-device 'ds1307@0x68?hour=12&minute=34&second=56' \
     --quiet --time 5
# expect: "12:34:56\n" output
```

Plus:
```bash
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

## Commit

```
fix(examples): i2c_ssd1306_rtc_clock — NAK last read so i2cstop fires STOP

Root cause: after master-ACK on the last byte of a multi-byte
read, the DS1307 slave keeps pulling SDA low to prepare bit 7
of the (unwanted) next byte. The emulator's bus state machine
(sw-cor24-emulator/src/cpu/i2c_bus.rs:149) detects STOP via the
effective SDA = master_sda && !slave_sda_pull, so my i2cstop's
SDA-up write is suppressed by the wired-AND and STOP never
registers. The bus stays in the read transaction, the slave
keeps streaming bytes (auto-incrementing pointer wraps through
all 8 registers and into the 56 bytes of RAM), and main_loop
lands its OLED traffic on a stale state machine. Visible
symptom: --dump-i2c shows 17+ RD entries with no STOP between
them, and the OLED renders wrong digits (often "00:40:40" when
the registers are all zero — the high nibble of one of the
runaway-read bytes happens to BCD-encode to '4').

Fix per standard i2c protocol: NAK the last byte instead of
ACKing. NAK = master releases SDA on the 9th clock pulse;
slave sees NAK and releases SDA too (slave_sda_pull = false).
Then i2cstop's SDA-up write actually rises the effective line
and the bus state machine fires STOP.

Implementation: new i2creadnak subroutine — verbatim copy of
i2cread but with master-NAK at the end (SDA=1, SCL=1, SCL=0
instead of SDA=0, SCL=1, SCL=0). The 3rd read in main_loop
(for H, the last register before i2cstop) calls i2creadnak.
The S and M reads continue to use i2cread so the slave keeps
auto-incrementing the pointer between them.

Verified via --dump-i2c: exactly 3 RDs + STOP per main_loop
iteration. OLED bytes decode correctly to the configured time.
No changes to shared primitives (i2cread, i2cwrite, i2cstart,
i2cstop), so i2c_ssd1306_hello.s and i2c_ds1307_read.s are
unaffected.

Refs: dcxas-fix-i2c-ssd1306-rtc-clock-read.md (dwxas, 2026-05-17).
```

## Wrap

`agentrail complete --done`. `dg-mark-pr` →
`pr/fix-i2c-ssd1306-rtc-clock-read`. Then bookkeeping branch
(strict superset).
