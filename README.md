# sw-cor24-x-assembler

COR24 assembler library — parses COR24 assembly language and produces machine code.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Dependencies

- [sw-cor24-isa](https://github.com/sw-embed/sw-cor24-isa) — ISA definitions (opcodes, encoding tables, branch constants); compile-time path-dep at `../sw-cor24-isa`.
- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) — runtime types (`CpuState`, `Executor`) used by the `.lgo` round-trip and execution-driven integration tests; declared as a dev-dependency at `../sw-cor24-emulator`. Production users of `cor24-asm` (binary or library) do not need this clone.

## Build

```bash
./scripts/build.sh
```

The build produces both the library and the `cor24-asm` CLI binary
at `target/<profile>/cor24-asm`.

## CLI

`cor24-asm` is the canonical command for `.s → .lgo`. It can also emit
raw machine-code bytes (`.bin`) and a human-readable listing (`.lst`).

```bash
cor24-asm prog.s                                       # writes prog.lgo
cor24-asm prog.s -o out.lgo                            # explicit .lgo output
cor24-asm prog.s --bin out.bin                         # raw machine code
cor24-asm prog.s -o out.lgo --bin out.bin --listing out.lst   # all three
cor24-asm prog.s --base-addr 0x1000 -o out.lgo         # assemble at non-zero base
cor24-asm -                                            # stdin → stdout (.lgo)
cor24-asm -V | --version                               # version
cor24-asm -h | --help                                  # usage
```

`--base-addr <addr>` shifts the location counter and bakes the base
into label resolution (so `la r0, foo` resolves to `base + offset_of(foo)`).
Output bytes still start at offset 0; only addresses (labels, `.lgo`
L-records, `.lst` columns) move. Accepts `0x...` hex, `...h` hex, or
decimal. Default 0.

Exit codes: `0` clean assembly, `1` assembly errors (one per line on
stderr), `2` usage / IO errors. When writing `.lgo` or `.bin` to
stdout, the destination must not be a terminal.

## Library Usage

```rust
use cor24_assembler::Assembler;

let mut asm = Assembler::new();
let result = asm.assemble("lc r0,42\nhalt:\nbra halt");
assert!(result.errors.is_empty());
println!("{} bytes of machine code", result.bytes.len());
```

## Links

- Blog: [Software Wrighter Lab](https://software-wrighter-lab.github.io/)
- Discord: [Join the community](https://discord.com/invite/Ctzk5uHggZ)
- YouTube: [Software Wrighter](https://www.youtube.com/@SoftwareWrighter)

## License

Copyright (c) 2026 Michael A Wright. MIT-licensed; see [LICENSE](LICENSE).
