// https://github.com/rust-lang/rust/issues/46379
#![allow(dead_code)]

use std::{
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};

use super::TestResult;

pub struct Cli {
    bin: PathBuf,
    config_dir: PathBuf,
}

impl Cli {
    pub fn new(config_dir: PathBuf) -> Self {
        Self {
            bin: PathBuf::from(env!("CARGO_BIN_EXE_ente-rs")),
            config_dir,
        }
    }

    pub fn run(&self, args: &[&str]) -> TestResult<Output> {
        Ok(command(&self.bin, &self.config_dir, args).output()?)
    }

    pub fn run_with_env(&self, args: &[&str], env: &[(&str, &str)]) -> TestResult<Output> {
        let mut command = command(&self.bin, &self.config_dir, args);
        command.envs(env.iter().copied());
        Ok(command.output()?)
    }

    pub fn run_ok(&self, args: &[&str]) -> TestResult<String> {
        output_stdout(args, self.run(args)?)
    }

    pub fn run_ok_with_env(&self, args: &[&str], env: &[(&str, &str)]) -> TestResult<String> {
        output_stdout(args, self.run_with_env(args, env)?)
    }

    pub fn run_with_stdin(&self, args: &[&str], stdin: &str) -> TestResult<Output> {
        let mut child = command(&self.bin, &self.config_dir, args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        child
            .stdin
            .take()
            .expect("ente-rs stdin should be piped")
            .write_all(stdin.as_bytes())?;

        Ok(child.wait_with_output()?)
    }

    pub fn run_ok_with_stdin(&self, args: &[&str], stdin: &str) -> TestResult<String> {
        output_stdout(args, self.run_with_stdin(args, stdin)?)
    }
}

fn command(bin: &Path, config_dir: &Path, args: &[&str]) -> Command {
    let mut command = Command::new(bin);
    command.args(args).env("ENTE_CLI_CONFIG_DIR", config_dir);
    command
}

fn output_stdout(args: &[&str], output: Output) -> TestResult<String> {
    if output.status.success() {
        Ok(String::from_utf8(output.stdout)?)
    } else {
        Err(format!(
            "ente-rs {} failed\nstatus: {}\nstdout:\n{}\nstderr:\n{}",
            args.join(" "),
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        )
        .into())
    }
}
