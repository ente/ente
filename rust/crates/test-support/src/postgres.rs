use std::{collections::HashMap, fs, path::PathBuf, process::Command};

use postgresql_embedded::Settings;
use postgresql_embedded::blocking::PostgreSQL;

use crate::{
    TestResult,
    net::{LOCAL_HOST, PORT_ATTEMPTS, free_port},
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
        self.execute_sql_on(self.database(), sql)
    }

    pub fn reset_database(&self) -> TestResult {
        self.execute_sql_on(
            "postgres",
            &format!("DROP DATABASE IF EXISTS {DATABASE} WITH (FORCE)"),
        )?;
        self.inner.create_database(DATABASE)?;
        Ok(())
    }

    pub fn query_sql(&self, sql: &str) -> TestResult<String> {
        self.psql(self.database(), &["-t", "-A"], sql)
    }

    fn execute_sql_on(&self, database: &str, sql: &str) -> TestResult {
        self.psql(database, &[], sql).map(drop)
    }

    fn psql(&self, database: &str, options: &[&str], sql: &str) -> TestResult<String> {
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
            database,
        ])
        .args(options)
        .args(["-c", sql])
        .output()?;
        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
        }
        Ok(String::from_utf8(output.stdout)?.trim().to_owned())
    }
}

pub fn start() -> TestResult<Postgres> {
    start_with(free_port)
}

fn start_with(mut next_port: impl FnMut() -> TestResult<u16>) -> TestResult<Postgres> {
    let mut attempts = 0;
    loop {
        attempts += 1;
        let mut inner = PostgreSQL::new(Settings {
            temporary: true,
            host: LOCAL_HOST.to_string(),
            port: next_port()?,
            installation_dir: install_dir()?,
            configuration: HashMap::from([("listen_addresses".into(), LOCAL_HOST.into())]),
            ..Settings::default()
        });
        inner.setup()?;
        if let Err(error) = inner.start() {
            let log =
                fs::read_to_string(inner.settings().data_dir.join("start.log")).unwrap_or_default();
            if attempts < PORT_ATTEMPTS && log.contains("Address already in use") {
                eprintln!(
                    "Postgres port {} is taken, retrying on another port",
                    inner.settings().port
                );
                continue;
            }
            return Err(format!("{error}\n{log}").into());
        }
        inner.create_database(DATABASE)?;
        return Ok(Postgres { inner });
    }
}

// postgresql_embedded defaults its binary to a `~/.theseus` dir in $HOME; keep
// that name but under the conventional cache directory instead.
fn install_dir() -> TestResult<PathBuf> {
    Ok(dirs::cache_dir()
        .ok_or("could not resolve a cache directory")?
        .join(".theseus")
        .join("postgresql"))
}

#[cfg(all(test, feature = "museum"))]
mod tests {
    use std::net::TcpListener;

    use super::*;

    #[test]
    fn moves_off_a_taken_port() -> TestResult {
        let holder = TcpListener::bind((LOCAL_HOST, 0))?;
        let taken = holder.local_addr()?.port();
        let mut first = Some(taken);
        let postgres = start_with(|| first.take().map_or_else(free_port, Ok))?;
        assert_ne!(postgres.port(), taken);
        postgres.execute_sql("SELECT 1")
    }
}
