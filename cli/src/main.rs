use std::ffi::OsString;
use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use cor24_assembler::{Assembler, AssemblyResult, lgo, listing};

const PKG_VERSION: &str = env!("CARGO_PKG_VERSION");

const USAGE: &str = "\
cor24-asm — COR24 cross-assembler

USAGE:
    cor24-asm <input.s>                                  Assemble; write <stem>.lgo next to input
    cor24-asm <input.s> -o <out.lgo>                     Explicit .lgo output path
    cor24-asm <input.s> --bin <out.bin>                  Raw machine-code bytes (no .lgo)
    cor24-asm <input.s> --bin <bin> --listing <lst>      Bytes + listing
    cor24-asm <input.s> -o <lgo> --bin <bin> --listing <lst>
                                                         All three artifacts
    cor24-asm -                                          Read .s from stdin, write .lgo to stdout
    cor24-asm -V | --version                             Print version
    cor24-asm -h | --help                                Print this help

EXIT CODES:
    0    clean assembly
    1    assembly errors (one per line on stderr)
    2    usage / IO errors

When writing .lgo or .bin to stdout, the destination must not be a terminal.
Redirect to a file or use an explicit path.";

fn main() -> ExitCode {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    match run(args) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("cor24-asm: {}", e);
            ExitCode::from(2)
        }
    }
}

#[derive(Debug)]
enum InputSource {
    File(PathBuf),
    Stdin,
}

impl InputSource {
    fn label(&self) -> String {
        match self {
            InputSource::File(p) => p.display().to_string(),
            InputSource::Stdin => "<stdin>".to_string(),
        }
    }
}

#[derive(Debug, Default)]
enum LgoSink {
    /// Write to <input-stem>.lgo when input is a file.
    #[default]
    AutoFromStem,
    /// Explicit -o path. `-` means stdout.
    Explicit(PathBuf),
    /// No .lgo output requested.
    None,
}

#[derive(Debug, Default)]
struct Cli {
    input: Option<InputSource>,
    lgo: LgoSink,
    bin: Option<PathBuf>,
    listing: Option<PathBuf>,
}

fn run(args: Vec<OsString>) -> Result<ExitCode, String> {
    let mut cli = Cli::default();
    let mut iter = args.into_iter();

    while let Some(arg) = iter.next() {
        let s = arg.to_string_lossy();
        match s.as_ref() {
            "-h" | "--help" => {
                println!("{}", USAGE);
                return Ok(ExitCode::SUCCESS);
            }
            "-V" | "--version" => {
                println!("cor24-asm {}", PKG_VERSION);
                return Ok(ExitCode::SUCCESS);
            }
            "-o" => {
                let v = iter
                    .next()
                    .ok_or_else(|| "-o requires an argument".to_string())?;
                cli.lgo = LgoSink::Explicit(PathBuf::from(v));
            }
            "--bin" => {
                let v = iter
                    .next()
                    .ok_or_else(|| "--bin requires an argument".to_string())?;
                cli.bin = Some(PathBuf::from(v));
            }
            "--listing" => {
                let v = iter
                    .next()
                    .ok_or_else(|| "--listing requires an argument".to_string())?;
                cli.listing = Some(PathBuf::from(v));
            }
            "-" => {
                if cli.input.is_some() {
                    return Err("multiple inputs not supported".to_string());
                }
                cli.input = Some(InputSource::Stdin);
            }
            other if other.starts_with("--") || (other.starts_with('-') && other.len() > 1) => {
                return Err(format!("unknown option '{}'", other));
            }
            _ => {
                if cli.input.is_some() {
                    return Err("multiple inputs not supported".to_string());
                }
                cli.input = Some(InputSource::File(PathBuf::from(arg)));
            }
        }
    }

    let input = cli
        .input
        .take()
        .ok_or_else(|| "no input file (use '-' for stdin); see --help".to_string())?;

    // If --bin is supplied without -o, suppress the default <stem>.lgo write.
    if cli.bin.is_some() && matches!(cli.lgo, LgoSink::AutoFromStem) {
        cli.lgo = LgoSink::None;
    }

    let source = read_input(&input).map_err(|e| format!("{}: {}", input.label(), e))?;

    let mut asm = Assembler::new();
    let result = asm.assemble(&source);

    if !result.errors.is_empty() {
        let label = input.label();
        for err in &result.errors {
            eprintln!("{}: {}", label, err);
        }
        return Ok(ExitCode::from(1));
    }

    write_outputs(&input, &cli, &result)?;
    Ok(ExitCode::SUCCESS)
}

fn read_input(src: &InputSource) -> io::Result<String> {
    match src {
        InputSource::File(p) => fs::read_to_string(p),
        InputSource::Stdin => {
            let mut buf = String::new();
            io::stdin().read_to_string(&mut buf)?;
            Ok(buf)
        }
    }
}

fn write_outputs(input: &InputSource, cli: &Cli, result: &AssemblyResult) -> Result<(), String> {
    match &cli.lgo {
        LgoSink::AutoFromStem => {
            let path = match input {
                InputSource::File(p) => default_lgo_path(p),
                InputSource::Stdin => {
                    // stdin with no -o: write .lgo to stdout (refuse TTY).
                    return write_lgo_to_stdout(result)
                        .and_then(|_| write_optional_extras(cli, result));
                }
            };
            write_lgo_to_path(&path, result)?;
        }
        LgoSink::Explicit(p) => {
            if p == Path::new("-") {
                write_lgo_to_stdout(result)?;
            } else {
                write_lgo_to_path(p, result)?;
            }
        }
        LgoSink::None => {}
    }
    write_optional_extras(cli, result)
}

fn write_optional_extras(cli: &Cli, result: &AssemblyResult) -> Result<(), String> {
    if let Some(p) = &cli.bin {
        if p == Path::new("-") {
            refuse_tty("cannot write .bin to a terminal")?;
            io::stdout()
                .write_all(&result.bytes)
                .map_err(|e| format!("writing .bin to stdout: {}", e))?;
        } else {
            fs::write(p, &result.bytes)
                .map_err(|e| format!("writing {}: {}", p.display(), e))?;
        }
    }
    if let Some(p) = &cli.listing {
        if p == Path::new("-") {
            listing::write(result, &mut io::stdout())
                .map_err(|e| format!("writing listing to stdout: {}", e))?;
        } else {
            let mut f = fs::File::create(p)
                .map_err(|e| format!("creating {}: {}", p.display(), e))?;
            listing::write(result, &mut f)
                .map_err(|e| format!("writing {}: {}", p.display(), e))?;
        }
    }
    Ok(())
}

fn default_lgo_path(input: &Path) -> PathBuf {
    let mut p = input.to_path_buf();
    p.set_extension("lgo");
    p
}

fn write_lgo_to_path(path: &Path, result: &AssemblyResult) -> Result<(), String> {
    let mut f =
        fs::File::create(path).map_err(|e| format!("creating {}: {}", path.display(), e))?;
    lgo::write(&result.bytes, 0, None, &mut f)
        .map_err(|e| format!("writing {}: {}", path.display(), e))
}

fn write_lgo_to_stdout(result: &AssemblyResult) -> Result<(), String> {
    refuse_tty("cannot write .lgo to a terminal")?;
    let mut out = io::stdout().lock();
    lgo::write(&result.bytes, 0, None, &mut out)
        .map_err(|e| format!("writing .lgo to stdout: {}", e))
}

fn refuse_tty(msg: &str) -> Result<(), String> {
    if io::stdout().is_terminal() {
        return Err(format!(
            "{} (redirect to a file, or use an explicit path)",
            msg
        ));
    }
    Ok(())
}
