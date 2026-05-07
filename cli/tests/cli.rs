use std::io::Write;
use std::process::{Command, Stdio};

use tempfile::TempDir;

const FIXTURE_SRC: &str = include_str!("fixtures/simple.s");

/// Machine code for `simple.s` (`lc r0,42 / halt: / bra halt`).
const FIXTURE_BYTES: &[u8] = &[0x44, 0x2A, 0x13, 0xFC];

fn cor24_asm() -> Command {
    Command::new(env!("CARGO_BIN_EXE_cor24-asm"))
}

fn write_fixture(dir: &TempDir) -> std::path::PathBuf {
    let p = dir.path().join("simple.s");
    std::fs::write(&p, FIXTURE_SRC).unwrap();
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
