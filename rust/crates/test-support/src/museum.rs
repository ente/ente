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

/// A running Museum for integration tests, backed by a temporary Postgres.
///
/// Created with [`Museum::run`], which boots both, runs the test, and tears
/// everything down on drop. The temporary directory is removed unless the test
/// fails, in which case it is retained for inspection.
pub struct Museum {
    _server: ChildProcess,
    _postgres: postgres::Postgres,
    _object_store: ObjectStore,
    temp_dir: TempDir,
    endpoint: String,
}

impl Museum {
    /// Boot a Museum, run `test` against it, then tear everything down.
    ///
    /// On failure the temporary directory is retained (its path is printed to
    /// stderr) so the museum and Postgres logs can be inspected.
    pub fn run(test: impl FnOnce(&Self) -> TestResult) -> TestResult {
        let mut museum = Self::start()?;
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

    /// Boot a Museum and run an asynchronous test on a Tokio runtime.
    pub fn run_async<F, Fut>(test: F) -> TestResult
    where
        F: FnOnce(String) -> Fut,
        Fut: Future<Output = TestResult>,
    {
        Self::run(|museum| tokio::runtime::Runtime::new()?.block_on(test(museum.endpoint.clone())))
    }

    fn start() -> TestResult<Self> {
        let server_dir = server_dir()?;
        let mut temp_dir = TempDir::new("ente-test")?;
        let log_dir = temp_dir.path().join("logs");
        let museum_port = free_port()?;
        let endpoint = format!("http://{LOCAL_HOST}:{museum_port}");
        let museum_config_file = temp_dir.path().join("museum.yaml");
        let museum_bin = temp_dir.path().join("museum");

        let result = (|| {
            let object_store = ObjectStore::start()?;
            server::write_config(&museum_config_file, &object_store.endpoint())?;
            let postgres = postgres::start()?;
            let server = server::start(
                &server_dir,
                &log_dir,
                &museum_config_file,
                museum_port,
                &museum_bin,
                &postgres,
            )?;
            Ok((postgres, object_store, server))
        })();

        let (postgres, object_store, server) = match result {
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
            endpoint,
        })
    }

    /// The base URL of the running Museum, e.g. `http://127.0.0.1:1234`.
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// A scratch directory tied to this Museum's lifetime, for test-local files.
    pub fn temp_dir(&self) -> &Path {
        self.temp_dir.path()
    }
}

/// The repository's `server/` directory, which Museum is run from.
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
