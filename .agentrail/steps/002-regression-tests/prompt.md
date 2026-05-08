Add tests proving the --base-addr CLI plumbing is correct, including a byte-identical regression fixture captured from the still-on-PATH `cor24-run --assemble --base-addr` (the deprecated binary the brief explicitly invokes for byte-identical regression).

Steps:

1. **Capture regression fixture from cor24-run** (do this BEFORE the CLI tests, while cor24-run is still on PATH):

   - Add `cli/tests/fixtures/with_la.s`:
     ```
     la r0, target
     target:
       lc r1, 99
     halt:
       bra halt
     ```
     This mirrors the test program in commit ba96d75. It exercises a forward `la` reference, which is what `--base-addr` actually shifts (label resolution baked into `la`).

   - Capture .bin:
     ```
     cor24-run --assemble cli/tests/fixtures/with_la.s \
       cli/tests/fixtures/with_la_at_0x100.bin /dev/null \
       --base-addr 0x100
     ```
     Verify it succeeds. (Note: cor24-run's --assemble takes positional `<in.s> <out.bin> <out.lst>` per ba96d75; `/dev/null` for the listing.)

   - Inspect with `xxd cli/tests/fixtures/with_la_at_0x100.bin` to confirm the la operand resolves to 0x000104 (la is 4 bytes; target is at base+4).

   - Commit the .bin as a fixture. It's tiny (~10 bytes); fine to track.

2. **Add CLI integration tests** in `cli/tests/cli.rs`:

   - `base_addr_hex` — `cor24-asm <simple.s> --base-addr 0x1000 -o <out>` exits 0; the output begins with `L001000`.

   - `base_addr_decimal_equals_hex` — `--base-addr 4096` produces the same .lgo bytes as `--base-addr 0x1000`.

   - `base_addr_h_suffix_equals_hex` — `--base-addr 1000h` produces the same .lgo bytes as `--base-addr 0x1000`.

   - `base_addr_invalid_exits_2` — `--base-addr abc` → exit 2, stderr mentions `--base-addr`.

   - `base_addr_default_unchanged` — without the flag, output equals the existing default (the existing `default_lgo_path` test already covers this; you can rely on it implicitly).

   - `base_addr_byte_identical_regression` — load `with_la.s` fixture, run `cor24-asm <fixture> --base-addr 0x100 --bin <out>`, assert exact equality with `with_la_at_0x100.bin` fixture bytes.

   - `base_addr_listing_shows_absolute_addresses` — assemble simple.s with `--base-addr 0x100 --listing <out>`; assert listing contains `0100:` (not `0000:`).

3. **Optional library-level test** in `src/lgo.rs`: confirm L-record addresses include the base_addr (you already have `roundtrip_through_loader_no_entry` with base 0x10; consider one with a higher base like 0x10000 to exercise the multi-line case).

4. Verify:
   - `cargo build --workspace`
   - `cargo clippy --workspace --tests -- -D warnings`
   - `cargo test --workspace` — all green

Commit with `test:` prefix and include `.agentrail/` deltas.