Implement the cor24-asm CLI binary. Replace the stub `cli/src/main.rs` with a real implementation, hand-rolled (no clap) — the surface is small enough that introducing a dep isn't worth it, and `cor24-dbg`'s emulator-side CLI is similarly hand-rolled.

CLI shape:

  cor24-asm <input.s>                                    # writes <stem>.lgo next to input
  cor24-asm <input.s> -o <out.lgo>                       # explicit .lgo output
  cor24-asm <input.s> --bin <out.bin>                    # raw bytes, no .lgo
  cor24-asm <input.s> --bin <out.bin> --listing <out.lst>
  cor24-asm <input.s> -o <out.lgo> --bin <out.bin> --listing <out.lst>
  cor24-asm -                                            # stdin → stdout (.lgo)
  cor24-asm -V | --version                               # version block
  cor24-asm -h | --help                                  # usage

Rules:
- If neither -o nor --bin is given (and input is not '-'), default output is `<stem>.lgo` next to the input.
- If both -o and --bin are given, both are written.
- --listing is independent of -o/--bin and may pair with either.
- Input '-' means read all of stdin; if no -o is given in stdin mode, write the .lgo to stdout. (--bin and --listing still take explicit paths.)
- Refuse to write binary content (.lgo or .bin) to a TTY: if stdout would be a terminal, print a clear error to stderr and exit 2. Use `std::io::IsTerminal` (`std::io::stdout().is_terminal()` is in std as of Rust 1.70).
- Exit codes:
    0 — clean assembly, all writes succeeded
    1 — assembly errors (printed to stderr, one per line; library returns `Vec<String>` errors which today don't carry location info — emit them as bare messages, prefixed with the input filename if known: `<input>: <msg>`)
    2 — usage / IO errors (bad flags, missing input file, IsTerminal refusal, write failures)
- -V output: print "cor24-asm <version>" using `env!(\"CARGO_PKG_VERSION\")`. The brief mentions vergen, but cor24-dbg's full vergen block requires a build.rs and dependencies; for this PR a simple version line with package version is sufficient — flag in the PR if you'd like vergen later. Keep -V to a single line so tests can string-match it.
- Library API used: `Assembler::new()`, `asm.assemble(source)`, `result.errors`, `result.bytes`, `result.lines` (the listing writer needs the full result, so we call `assemble` once and feed the same `AssemblyResult` to all three writers).
- The .lgo writer call uses `base_addr=0` and `entry=None` — defaults agreed for this PR.

Recommended structure of cli/src/main.rs:

  - `fn main()` parses argv, dispatches to `run(args) -> ExitCode` (or returns `i32`).
  - `enum InputSource { File(PathBuf), Stdin }`
  - `enum LgoSink { File(PathBuf), Stdout, AutoFromStem }` (AutoFromStem = derive `<stem>.lgo` from the input file)
  - Helper `read_input(src) -> io::Result<String>` and `open_writer_refusing_tty(path) -> io::Result<Box<dyn Write>>`
  - When writing to stdout for binary content, refuse if `is_terminal()`. When writing to a path, no TTY check (the path is unambiguous).
  - Print errors to stderr in this format: `eprintln!(\"{}: {}\", input_label, err);` where `input_label` is the path (or `<stdin>`).

Add `cli/Cargo.toml` dep on the lib (already there) and ensure `edition = \"2024\"` is set so `IsTerminal` works. No new external deps unless absolutely necessary.

Verify:
- `cargo build --workspace`
- `cargo clippy --workspace -- -D warnings`
- `cargo test --workspace` (no new tests yet — those land in step 5)
- Manual smoke: `target/debug/cor24-asm --help` shows usage; `target/debug/cor24-asm -V` prints a version line.

Commit with `feat:` prefix and include .agentrail/ deltas.