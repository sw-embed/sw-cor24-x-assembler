; Button Echo (MakerLisp): LED D2 follows S2 via shared IO_LEDSWDAT byte.
;
; Reproduces the 27-byte MakerLisp blinky_s2 program from the COR24-TB
; docs (see sw-cor24-emulator/tests/programs/blinky_s2.lgo and the
; disassembly in sw-cor24-emulator/docs/makerlisp-blinky_s2.md).
;
; Slightly different shape from button_echo.s: this variant keeps the
; loop body at offset 0x0000 and a startup block at offset 0x000E that
; sets sp to the top of EBR, parks r1 at the bottom of EBR, and jumps
; into the loop. Source order matters - the entry point depends on the
; loop body being exactly 14 bytes (0x0E).
;
; I/O: 0xFF0000 = IO_LEDSWDAT, bit 0
;        read  = button S2  (0 = pressed, 1 = released)
;        write = LED D2     (0 = on,      1 = off)
; Both ends are active-low, so a direct read -> write echo lights D2
; while S2 is held.

; --- loop body @ 0x0000 (entered from the startup block) ---
loop:
        push    fp
        push    r2
        push    r1
        mov     fp,sp
        la      r2,0xFF0000     ; r2 = IO_LEDSWDAT
spin:
        lb      r0,(r2)         ; r0 = switch byte (bit 0 = S2)
        sb      r0,(r2)         ; write same byte -> drives LED D2
        bra     spin            ; forever

; --- startup @ 0x000E (the entry point in blinky_s2.lgo's G record) ---
start:
        la      r0,0xFEEC00     ; top of EBR stack
        mov     sp,r0
        la      r1,0xFEE000     ; bottom of EBR (unused after this)
        la      ir,loop         ; absolute jump into the loop (never returns)
