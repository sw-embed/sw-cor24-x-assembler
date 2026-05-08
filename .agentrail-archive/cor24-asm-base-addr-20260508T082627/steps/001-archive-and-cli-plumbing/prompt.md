Wire the `--base-addr` flag into `cor24-asm`. Library already supports it via `Assembler::assemble_at(source, base_address)`; this step is CLI-only plumbing.

Concrete edits in `cli/src/main.rs`:

1. Add a `base_addr: u32` field to `Cli` (default 0).

2. Add a top-level helper `fn parse_numeric_addr(s: &str) -> Option<u32>` that accepts:
   - Hex with `0x` prefix (case-insensitive): `0x1000`, `0X1000`
   - Hex with trailing `h` suffix (case-insensitive): `1000h`, `1000H`
   - Plain decimal: `4096`
   Returns `None` for anything else. Mirror the reference impl in `git show ba96d75 -- '*/run.rs'`.

3. Add a parser arm:
   ```
   "--base-addr" => {
       let v = iter.next().ok_or_else(|| "--base-addr requires an argument".to_string())?;
       cli.base_addr = parse_numeric_addr(&v.to_string_lossy())
           .ok_or_else(|| format!("invalid --base-addr value '{}': expected hex (0x.../...h) or decimal", v.to_string_lossy()))?;
   }
   ```
   The error returned bubbles up via `run() -> Err(...)` to the existing exit-2 path in `main`.

4. Replace `asm.assemble(&source)` with `asm.assemble_at(&source, cli.base_addr)`.

5. Replace `lgo::write(&result.bytes, 0, None, ...)` everywhere with `lgo::write(&result.bytes, cli.base_addr, None, ...)`. Two callsites: `write_lgo_to_path` and `write_lgo_to_stdout`. Easiest: thread `base_addr` through as a parameter, or close over `cli` — your call.

6. USAGE block: add a `--base-addr <addr>` line under the invocation forms with a one-line description. Mention hex (`0x...` / `...h`) and decimal both accepted.

7. Verify:
   - `cargo build --workspace`
   - `cargo clippy --workspace --tests -- -D warnings`
   - `cargo test --workspace` (no new tests yet — those land in step 2)
   - Manual: `target/debug/cor24-asm cli/tests/fixtures/simple.s --base-addr 0x100 -o /tmp/x.lgo && cat /tmp/x.lgo` should show `L000100...` (was `L000000...` without the flag).

Commit message starting with `feat:` and include `.agentrail/` deltas (saga init + this step).
