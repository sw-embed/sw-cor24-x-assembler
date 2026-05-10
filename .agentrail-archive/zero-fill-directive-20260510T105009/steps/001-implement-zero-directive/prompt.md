Implement `.zero N` directive in `cor24-asm` per
`dcxas-zero-fill-directive.md`.

1. **`src/assembler.rs`** — in `handle_directive` (around line 222),
   add a new arm before the `.comm` block (so it's grouped with the
   output-emitting directives `.byte` / `.word`):

   ```rust
   ".zero" => {
       if parts.len() > 1
           && let Some(n) = self.parse_number(parts[1].trim_matches(','))
       {
           for _ in 0..n {
               self.output.push(0);
               self.address += 1;
           }
       }
   }
   ```

   Today `.zero` falls through the catch-all `_ => {}` arm and is
   silently a no-op; after this change it emits N zero bytes.

2. **Unit tests in `src/assembler.rs`** — match the style of the
   existing `.byte` / `.word` tests near line 1330. Add tests that
   cover the brief's full matrix:

   - `.zero N` produces N zero bytes (try N=5 and N=1024).
   - `.zero 0` is a no-op (assembles cleanly, contributes no
     bytes, no error).
   - **Byte-identity**: `.zero 8` produces the same `.bytes` as
     `.byte 0,0,0,0,0,0,0,0`. (This is the brief's primary
     correctness check — assemble both and assert
     `r1.bytes == r2.bytes`.)
   - `.zero` after `.data` works.
   - `.zero` after `.text` works (don't restrict — flat memory
     model; document this choice in the brief, no code change
     needed beyond a test that proves it).
   - Mixed: `.byte 1,2,3` + `.zero 4` + `.byte 5` produces
     `[1,2,3,0,0,0,0,5]` and labels resolve at the correct
     addresses.

3. **Integration test in `tests/integration_tests.rs`** — add a
   CLI/round-trip test analogous to existing CLI tests. Assemble a
   small fixture with a label followed by `.zero N` followed by
   non-zero data, write `.lgo`, and verify the bytes round-trip.
   If `--listing` is exercised in existing tests, mirror that.
   Match the file's existing test conventions (look at the
   neighboring tests; don't introduce a new helper if an existing
   one fits).

4. **Verify** the brief's full check runs clean:
   ```bash
   cargo build --workspace --release
   cargo test --workspace
   cargo clippy --workspace --all-targets --all-features -- -D warnings
   target/release/cor24-asm -V
   ```

5. **Commit** with this message:
   ```
   feat: add .zero N directive for bulk zero-fill

   .zero N emits N zero bytes at the current location counter,
   replacing the .byte 0,0,...,0 enumeration that bloats source
   files (e.g. SNOBOL4's sno_main.s sits at ~261 KB, ~97.7%
   zero-fill text). Output bytes are byte-identical to the
   spelled-out form.

   Spelling matches GNU as. Constant N only for v1; no .bss
   segment or loader changes — purely a source-density fix that
   works in both .text and .data under the flat memory model.

   Archives the prior depend-on-isa-not-emulator saga and
   initializes the zero-fill-directive saga.

   Unblocks dcpls-emit-zero-fill (PL/SW codegen) and dcsno's
   snobol4-runtime-split saga.
   ```
   Include `.agentrail/` deltas (archive of prior saga + new
   saga init + this step's begin/complete) in the same commit.

6. `agentrail complete --done`. `dg-mark-pr`. STOP.
