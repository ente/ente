use std::env;
use std::error::Error;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use camino::Utf8PathBuf;
use lib_flutter_rust_bridge_codegen::codegen::{
    self as frb_codegen, Config as FrbConfig, MetaConfig as FrbMetaConfig,
};
use uniffi_bindgen::bindings::{self, GenerateOptions, TargetLanguage};

type DynError = Box<dyn Error>;

struct UniffiCrate<'a> {
    crate_name: &'a str,
    crate_dir: PathBuf,
}

#[derive(Clone, Copy)]
enum NativeTarget {
    All,
    Ensu,
    Cast,
}

#[derive(Clone, Copy)]
enum FrbTarget {
    All,
    Shared,
    Photos,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), DynError> {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("native") => {
            let target = match args.next().as_deref() {
                None => NativeTarget::All,
                Some("ensu") => NativeTarget::Ensu,
                Some("cast") => NativeTarget::Cast,
                _ => return Err(usage_error()),
            };
            if args.next().is_some() {
                return Err(usage_error());
            }
            generate_native(target)
        }
        Some("frb") => {
            let target = match args.next().as_deref() {
                None => FrbTarget::All,
                Some("shared") => FrbTarget::Shared,
                Some("photos") => FrbTarget::Photos,
                _ => return Err(usage_error()),
            };
            if args.next().is_some() {
                return Err(usage_error());
            }
            generate_frb(target)
        }
        _ => Err(usage_error()),
    }
}

fn usage_error() -> DynError {
    "usage: cargo codegen <native [ensu|cast]|frb [shared|photos]>".into()
}

fn generate_native(target: NativeTarget) -> Result<(), DynError> {
    let rust_root = rust_root()?;

    if matches!(target, NativeTarget::All | NativeTarget::Ensu) {
        let ensu = UniffiCrate {
            crate_name: "ensu",
            crate_dir: rust_root.join("bindings/uniffi/ensu"),
        };
        generate_swift(&ensu, "mobile/native/apple/apps/ensu/Ensu/Generated")?;
        generate_kotlin(
            &ensu,
            "mobile/native/android/apps/ensu/rust/src/main/kotlin",
            "io/ente/ensu/bindings/ensu.kt",
        )?;
    }

    if matches!(target, NativeTarget::All | NativeTarget::Cast) {
        let cast = UniffiCrate {
            crate_name: "cast",
            crate_dir: rust_root.join("bindings/uniffi/cast"),
        };
        generate_swift(&cast, "mobile/native/apple/apps/cast/Cast/Generated")?;
        // TODO: Android cast bindings scaffold
        // generate_kotlin(
        //     &cast,
        //     "mobile/native/android/apps/cast/app/src/main/kotlin",
        //     "io/ente/cast/bindings/cast.kt",
        // )?;
    }

    Ok(())
}

fn generate_swift(uniffi_crate: &UniffiCrate<'_>, generated_rel: &str) -> Result<(), DynError> {
    let generated_dir = repo_root()?.join(generated_rel);
    write_generated_gitignore(&generated_dir)?;

    build_host_library(&uniffi_crate.crate_dir)?;
    remove_paths(&swift_generated_paths(
        &generated_dir,
        uniffi_crate.crate_name,
    ))?;
    generate_bindings(TargetLanguage::Swift, &generated_dir, uniffi_crate)?;

    sanitize_generated_swift_bindings(
        &generated_dir.join(format!("{}.swift", uniffi_crate.crate_name)),
        uniffi_crate.crate_name,
    )?;

    Ok(())
}

fn generate_kotlin(
    uniffi_crate: &UniffiCrate<'_>,
    out_rel: &str,
    generated_rel: &str,
) -> Result<(), DynError> {
    let rust_out_dir = repo_root()?.join(out_rel);
    let generated_path = rust_out_dir.join(generated_rel);
    if let Some(bindings_dir) = generated_path.parent() {
        write_generated_gitignore(bindings_dir)?;
    }

    build_host_library(&uniffi_crate.crate_dir)?;
    remove_path(&generated_path)?;
    generate_bindings(TargetLanguage::Kotlin, &rust_out_dir, uniffi_crate)?;

    Ok(())
}

fn write_generated_gitignore(dir: &Path) -> Result<(), DynError> {
    fs::create_dir_all(dir)?;
    let path = dir.join(".gitignore");
    fs::write(&path, "*\n!.gitignore\n")
        .map_err(|error| format!("failed to write {}: {error}", path.display()).into())
}

fn generate_frb(target: FrbTarget) -> Result<(), DynError> {
    let rust_root = rust_root()?;
    let repo_root = rust_root
        .parent()
        .ok_or("failed to resolve repo root from rust/apps/codegen")?;

    if matches!(target, FrbTarget::All | FrbTarget::Shared) {
        generate_frb_package(&repo_root.join("mobile/packages/rust"))?;
    }
    if matches!(target, FrbTarget::All | FrbTarget::Photos) {
        generate_frb_package(&repo_root.join("mobile/apps/photos"))?;
    }
    format_frb_bindings(target)
}

fn generate_frb_package(package_dir: &Path) -> Result<(), DynError> {
    let previous_dir = env::current_dir().map_err(|error| {
        format!("failed to capture current directory before generating FRB bindings: {error}")
    })?;

    env::set_current_dir(package_dir).map_err(|error| {
        format!(
            "failed to enter {} before generating FRB bindings: {error}",
            package_dir.display()
        )
    })?;

    let result = FrbConfig::from_files_auto().and_then(|config| {
        let config = FrbConfig::merge(
            FrbConfig {
                dart_fix: Some(false),
                ..Default::default()
            },
            config,
        );
        frb_codegen::generate(config, FrbMetaConfig { watch: false })
    });

    env::set_current_dir(&previous_dir).map_err(|error| {
        format!(
            "failed to restore current directory to {}: {error}",
            previous_dir.display()
        )
    })?;

    result?;

    Ok(())
}

fn format_frb_bindings(target: FrbTarget) -> Result<(), DynError> {
    let rust_root = rust_root()?;
    let mut command = Command::new("cargo");
    command.arg("fmt");
    match target {
        FrbTarget::All => {
            command
                .arg("-p")
                .arg("ente_rust")
                .arg("-p")
                .arg("ente_photos_rust");
        }
        FrbTarget::Shared => {
            command.arg("-p").arg("ente_rust");
        }
        FrbTarget::Photos => {
            command.arg("-p").arg("ente_photos_rust");
        }
    }
    command.current_dir(rust_root);
    run_command(
        &mut command,
        "failed to format generated FRB Rust bindings".to_owned(),
    )
}

fn rust_root() -> Result<PathBuf, DynError> {
    let root = env::current_dir()?;
    if !root.join("Cargo.toml").is_file() {
        return Err("run cargo codegen from the Rust workspace root".into());
    }
    Ok(root)
}

fn repo_root() -> Result<PathBuf, DynError> {
    Ok(rust_root()?
        .parent()
        .ok_or("failed to resolve repo root from rust/apps/codegen")?
        .to_path_buf())
}

fn target_dir() -> Result<PathBuf, DynError> {
    Ok(rust_root()?.join("target"))
}

fn build_host_library(crate_dir: &Path) -> Result<(), DynError> {
    let target_dir = target_dir()?;
    run_command(
        Command::new("cargo")
            .arg("build")
            .arg("--locked")
            .arg("--target-dir")
            .arg(target_dir)
            .current_dir(crate_dir),
        format!("failed to build {}", crate_dir.display()),
    )
}

fn swift_generated_paths(generated_dir: &Path, crate_name: &str) -> [PathBuf; 3] {
    [
        generated_dir.join(format!("{crate_name}.swift")),
        generated_dir.join(format!("{crate_name}FFI.h")),
        generated_dir.join(format!("{crate_name}FFI.modulemap")),
    ]
}

fn remove_path(path: &Path) -> Result<(), DynError> {
    match fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(format!("failed to remove {}: {error}", path.display()).into());
        }
    }

    Ok(())
}

fn remove_paths(paths: &[PathBuf]) -> Result<(), DynError> {
    for path in paths {
        remove_path(path)?;
    }

    Ok(())
}

fn generate_bindings(
    language: TargetLanguage,
    out_dir: &Path,
    uniffi_crate: &UniffiCrate<'_>,
) -> Result<(), DynError> {
    let source = target_dir()?.join("debug").join(format!(
        "{}{}{}",
        env::consts::DLL_PREFIX,
        uniffi_crate.crate_name,
        env::consts::DLL_SUFFIX
    ));
    let source = utf8_path(&source)?;
    let out_dir = utf8_path(out_dir)?;
    let previous_dir = env::current_dir().map_err(|error| {
        format!(
            "failed to capture current directory before generating {} bindings: {error}",
            uniffi_crate.crate_name
        )
    })?;

    env::set_current_dir(&uniffi_crate.crate_dir).map_err(|error| {
        format!(
            "failed to enter {} before generating bindings: {error}",
            uniffi_crate.crate_dir.display()
        )
    })?;

    let result = bindings::generate(GenerateOptions {
        languages: vec![language],
        source,
        out_dir,
        config_override: None,
        format: false,
        crate_filter: Some(uniffi_crate.crate_name.to_owned()),
        metadata_no_deps: false,
    });

    env::set_current_dir(&previous_dir).map_err(|error| {
        format!(
            "failed to restore current directory to {}: {error}",
            previous_dir.display()
        )
    })?;

    result?;

    Ok(())
}

fn sanitize_generated_swift_bindings(swift_file: &Path, crate_name: &str) -> Result<(), DynError> {
    let original = fs::read_to_string(swift_file)
        .map_err(|error| format!("failed to read {}: {error}", swift_file.display()))?;
    let free_call_prefix = format!("try! rustCall {{ uniffi_{crate_name}_fn_free_");

    let mut rewritten = String::with_capacity(original.len());
    let mut replaced = false;

    for segment in original.split_inclusive('\n') {
        let line = segment.strip_suffix('\n').unwrap_or(segment);
        let trimmed = line.trim_start();

        if trimmed.starts_with(&free_call_prefix) && trimmed.ends_with("(handle, $0) }") {
            let indent = &line[..line.len() - trimmed.len()];
            rewritten.push_str(indent);
            rewritten.push_str("// Avoid aborting the host app if Rust-side teardown fails during process shutdown.\n");
            rewritten.push_str(indent);
            rewritten.push_str(&line.replacen("try!", "try?", 1));
            if segment.ends_with('\n') {
                rewritten.push('\n');
            }
            replaced = true;
        } else {
            rewritten.push_str(segment);
        }
    }

    if replaced {
        fs::write(swift_file, rewritten)
            .map_err(|error| format!("failed to write {}: {error}", swift_file.display()))?;
    }

    Ok(())
}

fn utf8_path(path: &Path) -> Result<Utf8PathBuf, DynError> {
    Utf8PathBuf::from_path_buf(path.to_path_buf())
        .map_err(|path| format!("path is not valid UTF-8: {}", path.display()).into())
}

fn run_command(command: &mut Command, error_context: String) -> Result<(), DynError> {
    let program = command.get_program().to_os_string();
    let args = command
        .get_args()
        .map(OsStr::to_os_string)
        .collect::<Vec<_>>();
    let status = command.status().map_err(|error| {
        format!(
            "{error_context}: failed to start {}: {error}",
            render_command(&program, &args)
        )
    })?;

    if status.success() {
        return Ok(());
    }

    Err(format!(
        "{error_context}: {} exited with status {status}",
        render_command(&program, &args)
    )
    .into())
}

fn render_command(program: &OsStr, args: &[std::ffi::OsString]) -> String {
    let mut parts = Vec::with_capacity(args.len() + 1);
    parts.push(program.to_string_lossy().into_owned());
    parts.extend(args.iter().map(|arg| arg.to_string_lossy().into_owned()));
    parts.join(" ")
}
