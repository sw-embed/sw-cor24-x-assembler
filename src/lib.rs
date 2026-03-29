//! COR24 Assembler
//!
//! Parses COR24 assembly language and produces machine code.
//! Uses encoding tables extracted from the hardware decode ROM.
//!
//! COR24 is a C-Oriented RISC 24-bit architecture with:
//! - 3 general-purpose 24-bit registers (r0, r1, r2)
//! - 5 special registers: fp=r3, sp=r4, z=r5, iv=r6, ir=r7
//! - Single condition flag (C)
//! - Variable-length instructions (1, 2, or 4 bytes)
//! - 16MB address space (24-bit)
//! - Little-endian byte ordering

pub mod assembler;

// Re-export main types for convenience
pub use assembler::{AssembledLine, Assembler, AssemblyResult};

// Re-export emulator types that assembler consumers typically need
pub use cor24_emulator;
