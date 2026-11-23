use std::{
    fs,
    future::Future,
    path::{Path, PathBuf},
};

use uuid::Uuid;

use crate::{
    TestResult,
    net::{LOCAL_HOST, free_port},
    object_store::ObjectStore,
    postgres,
    process::ChildProcess,
    server,
};

pub struct Museum {
    _server: ChildProcess,
    _postgres: postgres::Postgres,
    _object_store: ObjectStore,
    temp_dir: TempDir,
    endpoint: String,
}

impl Museum {
    pub fn run(test: impl FnOnce(&Self) -> TestResult) -> TestResult {
        Self::run_with_env(&[], test)
    }

    pub fn run_with_env(
        env: &[(&str, &str)],
        test: impl FnOnce(&Self) -> TestResult,
    ) -> TestResult {
        let mut museum = Self::start(env, free_port)?;
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| test(&museum))) {
            Ok(Ok(())) => Ok(()),
            Ok(Err(error)) => {
                museum.temp_dir.retain();
                Err(error)
            }
            Err(panic) => {
                museum.temp_dir.retain();
                std::panic::resume_unwind(panic);
            }
        }
    }

    pub fn run_async<F, Fut>(test: F) -> TestResult
    where
        F: FnOnce(String) -> Fut,
        Fut: Future<Output = TestResult>,
    {
        Self::run(|museum| tokio::runtime::Runtime::new()?.block_on(test(museum.endpoint.clone())))
    }

    fn start(env: &[(&str, &str)], next_port: impl FnMut() -> TestResult<u16>) -> TestResult<Self> {
        let server_dir = server_dir()?;
        let mut temp_dir = TempDir::new("ente-test")?;
        let museum_config_file = temp_dir.path().join("museum.yaml");
        let museum_bin = temp_dir.path().join("museum");

        let result = (|| {
            let object_store = ObjectStore::start()?;
            server::write_config(&museum_config_file)?;
            let postgres = postgres::start(free_port)?;
            let (server, port) = server::start(
                &server_dir,
                env,
                &museum_config_file,
                &museum_bin,
                &postgres,
                &object_store.endpoint(),
                next_port,
            )?;
            Ok((postgres, object_store, server, port))
        })();

        let (postgres, object_store, server, port) = match result {
            Ok(processes) => processes,
            Err(error) => {
                temp_dir.retain();
                return Err(error);
            }
        };

        Ok(Self {
            _server: server,
            _postgres: postgres,
            _object_store: object_store,
            temp_dir,
            endpoint: format!("http://{LOCAL_HOST}:{port}"),
        })
    }

    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    pub fn temp_dir(&self) -> &Path {
        self.temp_dir.path()
    }

    pub fn object_store(&self) -> std::sync::Arc<crate::ObjectStoreControl> {
        self._object_store.control.clone()
    }

    pub fn execute_sql(&self, sql: &str) -> TestResult {
        self._postgres.execute_sql(sql)
    }
}

fn server_dir() -> TestResult<PathBuf> {
    let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo_dir = crate_dir
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .ok_or("failed to resolve repository directory")?;
    Ok(repo_dir.join("server"))
}

struct TempDir {
    path: PathBuf,
    retained: bool,
}

impl TempDir {
    fn new(prefix: &str) -> TestResult<Self> {
        let path = std::env::temp_dir().join(format!("{prefix}-{}", Uuid::new_v4()));
        fs::create_dir_all(&path)?;
        Ok(Self {
            path,
            retained: false,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn retain(&mut self) {
        eprintln!(
            "retaining integration test temp dir: {}",
            self.path.display()
        );
        self.retained = true;
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        if !self.retained {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}

#[cfg(all(test, feature = "museum"))]
mod tests {
    use std::net::TcpListener;

    use super::*;

    fn start_after(taken: u16) -> TestResult<Museum> {
        let mut first = Some(taken);
        Museum::start(&[], || first.take().map_or_else(free_port, Ok))
    }

    #[test]
    fn moves_off_a_port_another_server_answers_on() -> TestResult {
        let holder = TcpListener::bind((LOCAL_HOST, 0))?;
        let taken = holder.local_addr()?.port();
        let museum = start_after(taken)?;
        assert_ne!(museum.endpoint(), format!("http://{LOCAL_HOST}:{taken}"));
        Ok(())
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn moves_off_a_port_it_cannot_bind() -> TestResult {
        let listener = TcpListener::bind((LOCAL_HOST, 0))?;
        let holder = std::net::TcpStream::connect(listener.local_addr()?)?;
        let taken = holder.local_addr()?.port();
        let museum = start_after(taken)?;
        assert_ne!(museum.endpoint(), format!("http://{LOCAL_HOST}:{taken}"));
        let log = fs::read_to_string(museum.temp_dir().join("logs").join("museum.log"))?;
        assert!(log.contains(&format!(":{taken}: bind: address already in use")));
        Ok(())
    }
}
