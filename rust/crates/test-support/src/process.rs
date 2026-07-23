use std::{
    fs::{self, OpenOptions},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
};

use crate::TestResult;

pub struct ChildProcess {
    name: &'static str,
    child: Child,
    log_path: PathBuf,
}

impl ChildProcess {
    pub fn spawn(name: &'static str, command: &mut Command, log_dir: &Path) -> TestResult<Self> {
        fs::create_dir_all(log_dir)?;
        let log_path = log_dir.join(format!("{name}.log"));
        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;
        let child = command
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log))
            .spawn()?;
        Ok(Self {
            name,
            child,
            log_path,
        })
    }

    pub fn ensure_running(&mut self) -> TestResult {
        if let Some(status) = self.child.try_wait()? {
            return Err(format!(
                "{} exited early with {status}\n{}",
                self.name,
                self.log_summary()
            )
            .into());
        }
        Ok(())
    }

    pub fn log_summary(&self) -> String {
        match fs::read_to_string(&self.log_path) {
            Ok(log) => format!("{} log at {}\n{log}", self.name, self.log_path.display()),
            Err(error) => format!(
                "{} log at {} could not be read: {error}",
                self.name,
                self.log_path.display()
            ),
        }
    }
}

impl Drop for ChildProcess {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
