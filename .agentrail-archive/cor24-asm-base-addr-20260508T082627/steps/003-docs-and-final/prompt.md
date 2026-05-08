Last step. Update README and ship.

1. **README.md** — extend the `## CLI` section to mention `--base-addr`. Add a new bullet/example block after the existing examples:

   ```
   cor24-asm prog.s --base-addr 0x1000 -o out.lgo   # assemble at non-zero base
   ```

   And add a brief paragraph: `--base-addr <addr>` shifts the location counter and bakes the base into label resolution (so `la r0, foo` resolves to `base + offset_of(foo)`). Output bytes still start at offset 0; only addresses (labels, .lgo L-records, .lst columns) move. Accepts `0x...` hex, `...h` hex, or decimal. Default 0.

2. **Final verify**: `./scripts/build.sh` end-to-end; `target/debug/cor24-asm --help` shows the new OPTIONS section; `target/debug/cor24-asm cli/tests/fixtures/with_la.s --base-addr 0x100 --bin /tmp/check.bin && diff /tmp/check.bin cli/tests/fixtures/with_la_at_0x100.bin`.

3. Commit `docs:` prefix; include `.agentrail/` deltas.

4. `agentrail complete --done --summary ... --reward 1 --actions ...` to close the saga.

5. `dg-mark-pr` to rename `feat/cor24-asm-base-addr` → `pr/cor24-asm-base-addr`.

6. STOP after dg-mark-pr — no more changes.