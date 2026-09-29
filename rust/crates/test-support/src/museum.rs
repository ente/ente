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
            server::write_config(&museum_config_file)?;
            let postgres = postgres::start()?;
            let server = server::start(
                &server_dir,
                &log_dir,
                &museum_config_file,
                museum_port,
                &museum_bin,
                &postgres,
                &object_store.endpoint(),
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

    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    pub fn temp_dir(&self) -> &Path {
        self.temp_dir.path()
    }

    pub fn object_store(&self) -> std::sync::Arc<crate::ObjectStoreControl> {
        self._object_store.control.clone()
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
