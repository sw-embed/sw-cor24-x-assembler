use std::io::Write;
use std::process::{Command, Stdio};

use tempfile::TempDir;

const FIXTURE_SRC: &str = include_str!("fixtures/simple.s");
const WITH_LA_SRC: &str = include_str!("fixtures/with_la.s");

/// Machine code for `simple.s` (`lc r0,42 / halt: / bra halt`).
const FIXTURE_BYTES: &[u8] = &[0x44, 0x2A, 0x13, 0xFC];

/// Machine code for `with_la.s` assembled at base 0x100. The `la r0, target`
/// operand encodes 0x000104 (= base + offset of `target:` after the 4-byte la).
/// Provenance: hand-verified against the documented `--base-addr` semantics from
/// sw-cor24-emulator commit ba96d75. cor24-run on $PATH at PR-author time was
/// found to predate ba96d75 (printed the old "Wrote N bytes" success line and
/// did NOT bake the base into the `la` operand), so it was unsuitable as a
/// byte-identical reference; the fixture file is checked into the repo.
const WITH_LA_AT_0X100_BYTES: &[u8] = include_bytes!("fixtures/with_la_at_0x100.bin");

fn cor24_asm() -> Command {
    Command::new(env!("CARGO_BIN_EXE_cor24-asm"))
}

fn write_fixture(dir: &TempDir) -> std::path::PathBuf {
    let p = dir.path().join("simple.s");
    std::fs::write(&p, FIXTURE_SRC).unwrap();
    p
}

fn write_with_la_fixture(dir: &TempDir) -> std::path::PathBuf {
    let p = dir.path().join("with_la.s");
    std::fs::write(&p, WITH_LA_SRC).unwrap();
    p
}

#[test]
fn default_lgo_path() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);

    let out = cor24_asm().arg(&src).output().unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let lgo = src.with_extension("lgo");
    assert!(lgo.exists(), "{} should exist", lgo.display());
    let content = std::fs::read_to_string(&lgo).unwrap();
    assert!(content.starts_with('L'), "expected L-line, got: {:?}", content);
}

#[test]
fn explicit_lgo_output() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let out_path = dir.path().join("custom.lgo");

    let out = cor24_asm()
        .arg(&src)
        .arg("-o")
        .arg(&out_path)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let content = std::fs::read_to_string(&out_path).unwrap();
    assert!(content.starts_with('L'));
    // Default <stem>.lgo should NOT exist when -o is explicit.
    assert!(!src.with_extension("lgo").exists());
}

#[test]
fn bin_output_writes_exact_bytes() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let bin_path = dir.path().join("simple.bin");

    let out = cor24_asm()
        .arg(&src)
        .arg("--bin")
        .arg(&bin_path)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let bytes = std::fs::read(&bin_path).unwrap();
    assert_eq!(bytes, FIXTURE_BYTES);
}

#[test]
fn bin_suppresses_default_lgo() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let bin_path = dir.path().join("simple.bin");

    let out = cor24_asm()
        .arg(&src)
        .arg("--bin")
        .arg(&bin_path)
        .output()
        .unwrap();
    assert!(out.status.success());
    assert!(!src.with_extension("lgo").exists(),
        "default .lgo should not be written when --bin is given without -o");
}

#[test]
fn all_three_outputs() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let lgo = dir.path().join("simple.lgo");
    let bin = dir.path().join("simple.bin");
    let lst = dir.path().join("simple.lst");

    let out = cor24_asm()
        .arg(&src)
        .arg("-o").arg(&lgo)
        .arg("--bin").arg(&bin)
        .arg("--listing").arg(&lst)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    assert!(std::fs::metadata(&lgo).unwrap().len() > 0);
    assert_eq!(std::fs::read(&bin).unwrap(), FIXTURE_BYTES);
    let listing = std::fs::read_to_string(&lst).unwrap();
    assert!(listing.contains("halt:"), "listing missing halt label:\n{}", listing);
}

#[test]
fn stdin_to_stdout_pipe() {
    let mut child = cor24_asm()
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();

    child.stdin.as_mut().unwrap().write_all(FIXTURE_SRC.as_bytes()).unwrap();
    let out = child.wait_with_output().unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let stdout = String::from_utf8(out.stdout).unwrap();
    assert!(stdout.starts_with('L'), "stdout: {:?}", stdout);
    assert!(stdout.contains("442A13FC"), "expected hex in stdout: {:?}", stdout);
}

#[test]
fn broken_input_exits_1() {
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("bad.s");
    std::fs::write(&src, "this is not valid cor24 assembly\n").unwrap();

    let out = cor24_asm().arg(&src).output().unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(out.stdout.is_empty());
    assert!(!out.stderr.is_empty());
}

#[test]
fn missing_input_exits_2() {
    let dir = TempDir::new().unwrap();
    let missing = dir.path().join("does-not-exist.s");

    let out = cor24_asm().arg(&missing).output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let stderr = String::from_utf8(out.stderr).unwrap();
    assert!(
        stderr.contains("does-not-exist.s") || stderr.contains("No such file"),
        "stderr: {:?}", stderr
    );
}

#[test]
fn bad_flag_exits_2() {
    let out = cor24_asm().arg("--nope").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let stderr = String::from_utf8(out.stderr).unwrap();
    assert!(stderr.contains("--nope"), "stderr: {:?}", stderr);
}

#[test]
fn version_prints_cleanly() {
    let out = cor24_asm().arg("-V").output().unwrap();
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let line = stdout.trim();
    assert!(line.starts_with("cor24-asm "), "version output: {:?}", line);
    let version = &line["cor24-asm ".len()..];
    let parts: Vec<&str> = version.split('.').collect();
    assert_eq!(parts.len(), 3, "expected semver, got: {:?}", version);
    for p in parts {
        assert!(p.chars().all(|c| c.is_ascii_digit()), "non-digit in version: {:?}", p);
    }
}

#[test]
fn help_prints_usage() {
    let out = cor24_asm().arg("--help").output().unwrap();
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    assert!(stdout.contains("USAGE"), "stdout: {}", stdout);
}

#[test]
fn base_addr_hex_shifts_lgo_addresses() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let out_path = dir.path().join("custom.lgo");

    let out = cor24_asm()
        .arg(&src)
        .arg("--base-addr").arg("0x1000")
        .arg("-o").arg(&out_path)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let content = std::fs::read_to_string(&out_path).unwrap();
    assert!(content.starts_with("L001000"), "expected L001000... got: {:?}", content);
}

#[test]
fn base_addr_decimal_equals_hex() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let hex_path = dir.path().join("hex.lgo");
    let dec_path = dir.path().join("dec.lgo");

    cor24_asm().arg(&src).arg("--base-addr").arg("0x1000").arg("-o").arg(&hex_path).output().unwrap();
    cor24_asm().arg(&src).arg("--base-addr").arg("4096").arg("-o").arg(&dec_path).output().unwrap();

    assert_eq!(std::fs::read(&hex_path).unwrap(), std::fs::read(&dec_path).unwrap());
}

#[test]
fn base_addr_h_suffix_equals_hex() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let hex_path = dir.path().join("prefix.lgo");
    let sfx_path = dir.path().join("suffix.lgo");

    cor24_asm().arg(&src).arg("--base-addr").arg("0x1000").arg("-o").arg(&hex_path).output().unwrap();
    cor24_asm().arg(&src).arg("--base-addr").arg("1000h").arg("-o").arg(&sfx_path).output().unwrap();

    assert_eq!(std::fs::read(&hex_path).unwrap(), std::fs::read(&sfx_path).unwrap());
}

#[test]
fn base_addr_invalid_exits_2() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);

    let out = cor24_asm().arg(&src).arg("--base-addr").arg("not-a-number").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let stderr = String::from_utf8(out.stderr).unwrap();
    assert!(stderr.contains("--base-addr"), "stderr: {:?}", stderr);
}

#[test]
fn base_addr_missing_arg_exits_2() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);

    let out = cor24_asm().arg(&src).arg("--base-addr").output().unwrap();
    assert_eq!(out.status.code(), Some(2));
}

#[test]
fn base_addr_byte_identical_regression() {
    let dir = TempDir::new().unwrap();
    let src = write_with_la_fixture(&dir);
    let bin_path = dir.path().join("out.bin");

    let out = cor24_asm()
        .arg(&src)
        .arg("--base-addr").arg("0x100")
        .arg("--bin").arg(&bin_path)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let bytes = std::fs::read(&bin_path).unwrap();
    assert_eq!(bytes, WITH_LA_AT_0X100_BYTES,
        "byte mismatch — {} vs fixture {}",
        bytes.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(" "),
        WITH_LA_AT_0X100_BYTES.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(" "),
    );
}

#[test]
fn zero_directive_round_trips_through_cli() {
    // Mixed .zero and non-zero data; verify .lgo, .bin, and --listing all
    // see the zero-fill bytes at the right addresses and that labels resolve
    // through the gap.
    let dir = TempDir::new().unwrap();
    let src = dir.path().join("zero_mix.s");
    std::fs::write(
        &src,
        ".byte 1,2,3\n.zero 4\ntail:\n  .byte 9\n",
    )
    .unwrap();

    let lgo = dir.path().join("zero_mix.lgo");
    let bin = dir.path().join("zero_mix.bin");
    let lst = dir.path().join("zero_mix.lst");

    let out = cor24_asm()
        .arg(&src)
        .arg("-o").arg(&lgo)
        .arg("--bin").arg(&bin)
        .arg("--listing").arg(&lst)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    // .bin: byte-identical to spelled-out form
    assert_eq!(std::fs::read(&bin).unwrap(), vec![1, 2, 3, 0, 0, 0, 0, 9]);

    // .lgo: starts with L-line, encodes the same bytes
    let lgo_content = std::fs::read_to_string(&lgo).unwrap();
    assert!(lgo_content.starts_with('L'), "lgo: {:?}", lgo_content);
    assert!(lgo_content.contains("01020300000000"), "lgo missing payload: {}", lgo_content);
    assert!(lgo_content.contains("09"), "lgo missing trailing 09: {}", lgo_content);

    // --listing: tail label resolves at offset 7 (3 + 4 zero bytes)
    let listing = std::fs::read_to_string(&lst).unwrap();
    assert!(listing.contains("tail:"), "listing missing tail label:\n{}", listing);
    assert!(listing.contains("0007:"), "listing missing 0007: line:\n{}", listing);
}

#[test]
fn base_addr_listing_uses_absolute_addresses() {
    let dir = TempDir::new().unwrap();
    let src = write_fixture(&dir);
    let lst_path = dir.path().join("out.lst");

    let out = cor24_asm()
        .arg(&src)
        .arg("--base-addr").arg("0x100")
        .arg("--listing").arg(&lst_path)
        .output()
        .unwrap();
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let listing = std::fs::read_to_string(&lst_path).unwrap();
    assert!(listing.contains("0100:"), "listing missing 0100: line:\n{}", listing);
    assert!(!listing.contains("0000:"), "listing should not have 0000: line at base 0x100:\n{}", listing);
}
