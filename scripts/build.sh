#!/usr/bin/env bash
set -euo pipefail

echo "=== cargo build ==="
cargo build --workspace

echo "=== cargo clippy ==="
cargo clippy --workspace --tests -- -D warnings

echo "=== cargo test ==="
cargo test --workspace

echo "=== All checks passed ==="
