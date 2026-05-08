Add CLI integration tests at `cli/tests/cli.rs` that exec the built `cor24-asm` binary and assert on stdout/stderr/exit.

Use `env!(\"CARGO_BIN_EXE_cor24-asm\")` to locate the binary — cargo defines it for tests in the same package as the bin. No need for `assert_cmd`; `std::process::Command` is sufficient and keeps deps minimal.

Add a `tests/fixtures/` dir under `cli/` (e.g. `cli/tests/fixtures/simple.s`) with a small known-good source so we can compare output bytes deterministically:

    lc r0,42
    halt:
    bra halt

(That source produces 4 machine-code bytes and the listing already validated in step 4 manual smoke test.)

Test cases (one #[test] each unless trivially shared):

1. `default_lgo_path` — write a .s to a tempdir, run `cor24-asm <file>`, expect exit 0 and the file `<stem>.lgo` was created next to it with non-empty content.
2. `explicit_lgo_output` — `cor24-asm <file> -o <out>` writes to the explicit path. Verify content starts with `L`.
3. `bin_output` — `cor24-asm <file> --bin <out>` writes the raw bytes (4 bytes for the fixture). Verify exact bytes against the known machine code from `lc r0,42 / halt: / bra halt`: 0x44 0x2A 0x13 0xFC.
4. `bin_suppresses_default_lgo` — when --bin is given without -o, NO `<stem>.lgo` is written next to the input.
5. `all_three_outputs` — `cor24-asm <file> -o <lgo> --bin <bin> --listing <lst>` writes all three with non-empty content.
6. `stdin_to_stdout_pipe` — stdin .s, no -o, capture stdout, assert it parses as .lgo (starts with `L`, contains the expected hex). Use Stdio::piped() and write to child stdin.
7. `broken_input_exits_1` — assembly errors → exit 1, stderr non-empty, stdout empty.
8. `missing_input_exits_2` — non-existent file → exit 2, stderr mentions the path.
9. `bad_flag_exits_2` — `--nope` → exit 2.
10. `version_prints_cleanly` — `-V` → exit 0, stdout matches `^cor24-asm \d+\.\d+\.\d+$` (single line).
11. `help_prints_usage` — `--help` → exit 0, stdout contains "USAGE".

Use `tempfile` crate for temp dirs (it's the standard Rust crate; add as a `[dev-dependencies]` in `cli/Cargo.toml`). If you want to avoid the dep, use `std::env::temp_dir()` + a unique subdir (timestamp + pid) cleaned up at end. Whichever is simpler — the tempfile crate is widely used and trivial.

Helper to keep tests readable:

    fn cor24_asm() -> Command { Command::new(env!("CARGO_BIN_EXE_cor24-asm")) }

Wire into `cli/Cargo.toml`:

    [dev-dependencies]
    tempfile = "3"   # if used

Verify:
- `cargo build --workspace`
- `cargo clippy --workspace --tests -- -D warnings`
- `cargo test --workspace` — all tests pass

Commit with `test:` prefix and include `.agentrail/` deltas.