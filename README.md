# sw-cor24-x-assembler

COR24 assembler library — parses COR24 assembly language and produces machine code.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Dependencies

- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) — ISA definitions and CPU types

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
cor24-asm -                                            # stdin → stdout (.lgo)
cor24-asm -V | --version                               # version
cor24-asm -h | --help                                  # usage
```

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
