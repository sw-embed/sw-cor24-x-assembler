//! Listing (.lst) writer.
//!
//! Reproduces the exact format historically emitted by
//! `cor24-emu --assemble`. Downstream tooling parses these listings;
//! the column layout (including the 1-column offset between the
//! bytes branch and the source-only branch) is preserved verbatim
//! so this writer is a drop-in replacement for that emitter.

use std::io::{self, Write};

use crate::AssemblyResult;

pub fn write<W: Write>(result: &AssemblyResult, w: &mut W) -> io::Result<()> {
    for line in &result.lines {
        if !line.bytes.is_empty() {
            let bytes: String = line.bytes.iter().map(|b| format!("{:02X} ", b)).collect();
            writeln!(
                w,
                "{:04X}: {:14} {}",
                line.address,
                bytes.trim(),
                line.source
            )?;
        } else if !line.source.is_empty() {
            writeln!(w, "                    {}", line.source)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AssembledLine, Assembler, AssemblyResult};
    use std::collections::HashMap;

    fn render(result: &AssemblyResult) -> String {
        let mut buf = Vec::new();
        write(result, &mut buf).unwrap();
        String::from_utf8(buf).unwrap()
    }

    fn empty() -> AssemblyResult {
        AssemblyResult {
            bytes: Vec::new(),
            lines: Vec::new(),
            errors: Vec::new(),
            labels: HashMap::new(),
        }
    }

    #[test]
    fn empty_result_writes_nothing() {
        assert_eq!(render(&empty()), "");
    }

    #[test]
    fn bytes_line_format() {
        let mut r = empty();
        r.lines.push(AssembledLine {
            address: 0x10,
            bytes: vec![0x80, 0x65],
            source: "  push fp".to_string(),
            label: None,
        });
        assert_eq!(render(&r), "0010: 80 65            push fp\n");
    }

    #[test]
    fn source_only_line_format() {
        let mut r = empty();
        r.lines.push(AssembledLine {
            address: 0x00,
            bytes: vec![],
            source: "halt:".to_string(),
            label: Some("halt".to_string()),
        });
        assert_eq!(render(&r), "                    halt:\n");
    }

    #[test]
    fn mixed_lines() {
        let mut r = empty();
        r.lines.push(AssembledLine {
            address: 0x00,
            bytes: vec![0x80],
            source: "  push fp".to_string(),
            label: None,
        });
        r.lines.push(AssembledLine {
            address: 0x01,
            bytes: vec![],
            source: "halt:".to_string(),
            label: Some("halt".to_string()),
        });
        assert_eq!(
            render(&r),
            "0000: 80               push fp\n                    halt:\n",
        );
    }

    #[test]
    fn empty_source_and_bytes_emits_nothing() {
        let mut r = empty();
        r.lines.push(AssembledLine {
            address: 0x00,
            bytes: vec![],
            source: String::new(),
            label: None,
        });
        assert_eq!(render(&r), "");
    }

    #[test]
    fn roundtrip_via_assembler() {
        let mut asm = Assembler::new();
        let result = asm.assemble("lc r0,42\nhalt:\nbra halt");
        assert!(result.errors.is_empty(), "errors: {:?}", result.errors);

        let out = render(&result);
        assert!(!out.is_empty());
        let has_label_line = out
            .lines()
            .any(|line| line.starts_with("                    ") && line.contains("halt:"));
        assert!(has_label_line, "expected label line for halt:\n{}", out);
    }
}
