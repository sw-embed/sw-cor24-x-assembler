# sw-cor24-x-assembler

COR24 assembler library — parses COR24 assembly language and produces machine code.

Part of the [COR24 ecosystem](https://github.com/sw-embed/sw-cor24-project).

## Dependencies

- [sw-cor24-emulator](https://github.com/sw-embed/sw-cor24-emulator) — ISA definitions and CPU types

## Build

```bash
./scripts/build.sh
```

## Usage

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
