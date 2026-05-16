Apply dwxas's format-patch for `button_echo_makerlisp.s` and ship
through the dcxas relay flow. Per
`dcxas-makerlisp-button-echo.md`.

## 1. Apply the patch

```bash
git am /disk1/github/softwarewrighter/devgroup/tools/briefs/0001-feat-examples-add-Button-Echo-MakerLisp-variant.patch
```

This creates one commit authored by dwxas with the exact contents
described in the brief. Do NOT amend it (the format-patch exists
to preserve authorship).

If `git am` reports merge conflicts on `tests/integration_tests.rs`
(possible if the file has shifted since dwxas branched), resolve
the hunks by hand to match the patch's intent — register
`("Button Echo (MakerLisp)", ...)` in `examples()`, add to
`non_halting` — then `git am --continue`.

## 2. Verify

```bash
cargo build --workspace --release
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
target/release/cor24-asm -V
```

Spot-check the new fixture assembles and matches the upstream
byte string:

```bash
target/release/cor24-asm src/examples/assembler/button_echo_makerlisp.s -o /tmp/mlbe.lgo
cat /tmp/mlbe.lgo
# expect: L000000807F7E652B0000FF2E00820013F82900ECFE662A00E0FEC7000000
```

## 3. Wrap

`agentrail complete --done`. `dg-mark-pr` →
`pr/makerlisp-button-echo`. Then post-complete bookkeeping branch
→ `pr/makerlisp-button-echo-saga-complete`. STOP.

The agentrail saga-setup commit (this commit, made before `git am`)
should already be present and contains the archive of the prior
saga + init + step setup for this saga. Do not amend it after
`git am` — the two commits coexist on the branch in this order:

1. `saga: archive lgo-compact-flag and start makerlisp-button-echo`
   (dcxas, .agentrail/* changes only)
2. `feat(examples): add Button Echo (MakerLisp) variant`
   (dwxas, code changes only)
