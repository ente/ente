use std::{path::PathBuf, process::Command};

use postgresql_embedded::Settings;
use postgresql_embedded::blocking::PostgreSQL;

use crate::{
    TestResult,
    net::{LOCAL_HOST, free_port},
};

const DATABASE: &str = "ente_test";

pub struct Postgres {
    inner: PostgreSQL,
}

impl Postgres {
    pub fn host(&self) -> &str {
        &self.inner.settings().host
    }

    pub fn port(&self) -> u16 {
        self.inner.settings().port
    }

    pub fn username(&self) -> &str {
        &self.inner.settings().username
    }

    pub fn password(&self) -> &str {
        &self.inner.settings().password
    }

    pub fn database(&self) -> &str {
        DATABASE
    }

    pub fn execute_sql(&self, sql: &str) -> TestResult {
        let output = Command::new(
            self.inner
                .settings()
                .binary_dir()
                .join(format!("psql{}", std::env::consts::EXE_SUFFIX)),
        )
        .env("PGPASSWORD", self.password())
        .args([
            "-X",
            "-v",
            "ON_ERROR_STOP=1",
            "-h",
            self.host(),
            "-p",
            &self.port().to_string(),
            "-U",
            self.username(),
            "-d",
            self.database(),
            "-c",
            sql,
        ])
        .output()?;
        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
        }
        Ok(())
    }
}

pub fn start() -> TestResult<Postgres> {
    let settings = Settings {
        temporary: true,
        host: LOCAL_HOST.to_string(),
        port: free_port()?,
        installation_dir: install_dir()?,
        ..Settings::default()
    };
    let mut inner = PostgreSQL::new(settings);
    inner.setup()?;
    inner.start()?;
    inner.create_database(DATABASE)?;
    Ok(Postgres { inner })
}

// postgresql_embedded defaults its binary to a `~/.theseus` dir in $HOME; keep
// that name but under the conventional cache directory instead.
fn install_dir() -> TestResult<PathBuf> {
    Ok(dirs::cache_dir()
        .ok_or("could not resolve a cache directory")?
        .join(".theseus")
        .join("postgresql"))
}
