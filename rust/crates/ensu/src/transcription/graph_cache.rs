use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use ente_ensu_crypto::{Sha256Hasher, sha256};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub(super) const GRAPHS: [&str; 3] = [
    "encoder-model.int8.onnx",
    "decoder_joint-model.int8.onnx",
    "nemo128.onnx",
];
pub(super) const SOURCES: [&str; 4] = [GRAPHS[0], GRAPHS[1], GRAPHS[2], "vocab.txt"];
const SCHEMA: u32 = 2;
const CACHE_DIRECTORY: &str = "ensu-voice-onnx-v1";
const MAX_BYTES: u64 = 1536 * 1024 * 1024;
const MAX_MANIFEST: u64 = 64 * 1024;

pub(super) enum LoadPlan<'a> {
    Source { save_to: Option<&'a Path> },
    Cached { directory: &'a Path },
}

pub(super) struct GraphCache {
    root: PathBuf,
    device: String,
    verified: Mutex<Option<Verified>>,
}

#[derive(PartialEq, Eq)]
struct Verified {
    recipe: String,
    sources: Vec<SourceStamp>,
    files: Vec<SourceStamp>,
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
struct SourceStamp {
    bytes: u64,
    modified_ns: u128,
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
    #[cfg(unix)]
    changed_secs: i64,
    #[cfg(unix)]
    changed_ns: i64,
}

#[derive(Serialize, Deserialize, PartialEq, Eq)]
struct Artifact {
    bytes: u64,
    sha256: String,
}

#[derive(Serialize, Deserialize)]
struct Manifest {
    schema: u32,
    recipe: String,
    source_stamps: Vec<SourceStamp>,
    #[cfg(not(unix))]
    source_sha256: Vec<String>,
    artifacts: Vec<Artifact>,
}

struct Staging(PathBuf);
impl Drop for Staging {
    fn drop(&mut self) {
        let _ = remove_owned_directory(&self.0);
    }
}

impl GraphCache {
    pub fn new(cache_directory: PathBuf, device_identity: String) -> Self {
        Self {
            root: cache_directory.join(CACHE_DIRECTORY),
            device: device_identity,
            verified: Mutex::new(None),
        }
    }

    pub fn load<T, E>(
        &self,
        model_dir: &Path,
        runtime_configuration: &str,
        may_build: bool,
        mut loader: impl FnMut(LoadPlan<'_>) -> Result<T, E>,
    ) -> Result<T, E> {
        let Some((_lock, stamps)) = self.lock_and_stat(model_dir) else {
            return loader(LoadPlan::Source { save_to: None });
        };
        let recipe = digest_bytes(
            format!(
                "schema={SCHEMA};backend=ensu-parakeet-v1;ort-api={};os={};arch={};device={};{runtime_configuration}",
                ort::MINOR_VERSION,
                std::env::consts::OS,
                std::env::consts::ARCH,
                self.device,
            )
            .as_bytes(),
        );
        let ready = self.root.join("ready");
        let fingerprint = cache_fingerprint(&ready, &recipe, &stamps).ok();
        let already_verified = cfg!(unix)
            && fingerprint.as_ref().is_some_and(|fingerprint| {
                self.verified
                    .lock()
                    .ok()
                    .is_some_and(|v| v.as_ref() == Some(fingerprint))
            });
        if validate(&ready, model_dir, &recipe, &stamps, already_verified).is_ok()
            && let Ok(model) = loader(LoadPlan::Cached { directory: &ready })
            && source_stamps(model_dir).ok().as_ref() == Some(&stamps)
            && cache_fingerprint(&ready, &recipe, &stamps).ok() == fingerprint
        {
            if let Ok(mut verified) = self.verified.lock() {
                *verified = fingerprint;
            }
            return Ok(model);
        }
        if let Ok(mut verified) = self.verified.lock() {
            *verified = None;
        }
        if !may_build || self.clean_for_build().is_err() {
            return loader(LoadPlan::Source { save_to: None });
        }
        let staging = Staging(self.root.join(format!(".build-{}", Uuid::new_v4())));
        if fs::create_dir(&staging.0).is_err() {
            return loader(LoadPlan::Source { save_to: None });
        }
        if stamps.last().is_none_or(|stamp| stamp.bytes > MAX_BYTES)
            || fs::copy(model_dir.join("vocab.txt"), staging.0.join("vocab.txt")).is_err()
        {
            return loader(LoadPlan::Source { save_to: None });
        }
        #[cfg(not(unix))]
        let Ok(source_sha256) = source_hashes(model_dir) else {
            return loader(LoadPlan::Source { save_to: None });
        };
        let Ok(model) = loader(LoadPlan::Source {
            save_to: Some(&staging.0),
        }) else {
            drop(staging);
            return loader(LoadPlan::Source { save_to: None });
        };
        let publish = (|| -> io::Result<()> {
            if source_stamps(model_dir)? != stamps {
                return Err(invalid_cache());
            }
            let artifacts = artifacts(&staging.0)?;
            let manifest = Manifest {
                schema: SCHEMA,
                recipe: recipe.clone(),
                source_stamps: stamps.clone(),
                #[cfg(not(unix))]
                source_sha256,
                artifacts,
            };
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(staging.0.join("manifest.json"))?;
            file.write_all(&serde_json::to_vec(&manifest)?)?;
            file.sync_all()?;
            fs::rename(&staging.0, &ready)?;
            Ok(())
        })();
        if publish.is_ok()
            && let Ok(mut verified) = self.verified.lock()
        {
            *verified = cache_fingerprint(&ready, &recipe, &stamps).ok();
        }
        Ok(model)
    }

    fn lock_and_stat(&self, model_dir: &Path) -> Option<(File, Vec<SourceStamp>)> {
        fs::create_dir_all(&self.root).ok()?;
        if !fs::symlink_metadata(&self.root).ok()?.is_dir() {
            return None;
        }
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.root.join(".lock"))
            .ok()?;
        lock.try_lock().ok()?;
        Some((lock, source_stamps(model_dir).ok()?))
    }

    fn clean_for_build(&self) -> io::Result<()> {
        remove_owned_directory(&self.root.join("ready"))?;
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            let name = entry.file_name();
            if name
                .to_str()
                .and_then(|s| s.strip_prefix(".build-"))
                .and_then(|s| Uuid::parse_str(s).ok())
                .is_some()
            {
                remove_owned_directory(&entry.path())?;
            }
        }
        Ok(())
    }
}

fn source_stamps(model_dir: &Path) -> io::Result<Vec<SourceStamp>> {
    stamps_for(model_dir, &SOURCES)
}

fn cache_fingerprint(ready: &Path, recipe: &str, sources: &[SourceStamp]) -> io::Result<Verified> {
    Ok(Verified {
        recipe: recipe.into(),
        sources: sources.to_vec(),
        files: stamps_for(
            ready,
            &[
                GRAPHS[0],
                GRAPHS[1],
                GRAPHS[2],
                "vocab.txt",
                "manifest.json",
            ],
        )?,
    })
}

fn stamps_for(directory: &Path, names: &[&str]) -> io::Result<Vec<SourceStamp>> {
    names
        .iter()
        .map(|name| {
            let metadata = fs::symlink_metadata(directory.join(name))?;
            if !metadata.is_file() || metadata.len() == 0 {
                return Err(invalid_cache());
            }
            let modified_ns = metadata
                .modified()?
                .duration_since(UNIX_EPOCH)
                .map_err(|_| invalid_cache())?
                .as_nanos();
            #[cfg(unix)]
            use std::os::unix::fs::MetadataExt;
            Ok(SourceStamp {
                bytes: metadata.len(),
                modified_ns,
                #[cfg(unix)]
                device: metadata.dev(),
                #[cfg(unix)]
                inode: metadata.ino(),
                #[cfg(unix)]
                changed_secs: metadata.ctime(),
                #[cfg(unix)]
                changed_ns: metadata.ctime_nsec(),
            })
        })
        .collect()
}

#[cfg(not(unix))]
fn source_hashes(model_dir: &Path) -> io::Result<Vec<String>> {
    SOURCES
        .iter()
        .map(|name| digest_file(&model_dir.join(name)).map(|a| a.sha256))
        .collect()
}

fn validate(
    ready: &Path,
    model_dir: &Path,
    recipe: &str,
    stamps: &[SourceStamp],
    already_verified: bool,
) -> io::Result<()> {
    if !fs::symlink_metadata(ready)?.is_dir() {
        return Err(invalid_cache());
    }
    let path = ready.join("manifest.json");
    let metadata = fs::symlink_metadata(&path)?;
    if !metadata.is_file() || metadata.len() > MAX_MANIFEST {
        return Err(invalid_cache());
    }
    let mut bytes = Vec::new();
    File::open(path)?
        .take(MAX_MANIFEST + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_MANIFEST {
        return Err(invalid_cache());
    }
    let manifest: Manifest = serde_json::from_slice(&bytes)?;
    if manifest.schema != SCHEMA
        || manifest.recipe != recipe
        || manifest.source_stamps != stamps
        || manifest.artifacts.len() != SOURCES.len()
    {
        return Err(invalid_cache());
    }
    #[cfg(not(unix))]
    if source_hashes(model_dir)? != manifest.source_sha256 {
        return Err(invalid_cache());
    }
    if already_verified {
        validate_directory_entries(ready)?;
        let bytes: u64 = manifest.artifacts.iter().map(|g| g.bytes).sum();
        if bytes > MAX_BYTES {
            return Err(invalid_cache());
        }
        return Ok(());
    }
    if artifacts(ready)? != manifest.artifacts || source_stamps(model_dir)? != stamps {
        return Err(invalid_cache());
    }
    Ok(())
}

fn artifacts(directory: &Path) -> io::Result<Vec<Artifact>> {
    let mut total = 0;
    let mut artifacts = Vec::new();
    for name in SOURCES {
        let artifact = digest_file(&directory.join(name))?;
        total += artifact.bytes;
        if total > MAX_BYTES {
            return Err(invalid_cache());
        }
        artifacts.push(artifact);
    }
    validate_directory_entries(directory)?;
    Ok(artifacts)
}

fn validate_directory_entries(directory: &Path) -> io::Result<()> {
    for entry in fs::read_dir(directory)? {
        let name = entry?.file_name();
        if !SOURCES.iter().any(|expected| name == *expected) && name != "manifest.json" {
            return Err(invalid_cache());
        }
    }
    Ok(())
}

fn digest_file(path: &Path) -> io::Result<Artifact> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_file() || metadata.len() == 0 || metadata.len() > MAX_BYTES {
        return Err(invalid_cache());
    }
    let mut file = File::open(path)?;
    let mut hasher = Sha256Hasher::new();
    let mut buffer = vec![0_u8; 64 * 1024];
    let mut bytes = 0;
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        bytes += read as u64;
        if bytes > MAX_BYTES {
            return Err(invalid_cache());
        }
        hasher.update(&buffer[..read]);
    }
    if bytes != metadata.len() {
        return Err(invalid_cache());
    }
    Ok(Artifact {
        bytes,
        sha256: hex(&hasher.finalize()),
    })
}

fn digest_bytes(bytes: &[u8]) -> String {
    hex(&sha256(bytes))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn invalid_cache() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "Invalid voice graph cache")
}
fn remove_owned_directory(path: &Path) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() => fs::remove_dir_all(path),
        Ok(_) => fs::remove_file(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct Fixture {
        temp: tempfile::TempDir,
        source: PathBuf,
        cache: GraphCache,
        loads: RefCell<Vec<&'static str>>,
    }

    impl Fixture {
        fn new() -> Self {
            let temp = tempfile::tempdir().unwrap();
            let source = temp.path().join("source");
            fs::create_dir(&source).unwrap();
            for name in SOURCES {
                fs::write(source.join(name), name.as_bytes()).unwrap();
            }
            let cache = GraphCache::new(temp.path().join("cache"), "phone-a".into());
            Self {
                temp,
                source,
                cache,
                loads: RefCell::new(Vec::new()),
            }
        }

        fn load(&self, recipe: &str) -> String {
            self.cache
                .load(&self.source, recipe, true, |plan| self.loader(plan))
                .unwrap()
        }

        fn loader(&self, plan: LoadPlan<'_>) -> io::Result<String> {
            let (directory, save_to) = match plan {
                LoadPlan::Source { save_to } => {
                    self.loads.borrow_mut().push(if save_to.is_some() {
                        "build"
                    } else {
                        "source"
                    });
                    (self.source.as_path(), save_to)
                }
                LoadPlan::Cached { directory } => {
                    self.loads.borrow_mut().push("hit");
                    (directory, None)
                }
            };
            let mut result = String::new();
            for name in GRAPHS {
                let bytes = fs::read(directory.join(name))?;
                if let Some(save_to) = save_to {
                    fs::write(save_to.join(name), &bytes)?;
                }
                result.push_str(&digest_bytes(&bytes));
            }
            Ok(result)
        }

        fn ready(&self) -> PathBuf {
            self.cache.root.join("ready")
        }
    }

    #[test]
    fn deferred_load_reuses_but_never_builds_graphs() {
        let f = Fixture::new();
        let expected = f
            .cache
            .load(&f.source, "runtime-a", false, |plan| f.loader(plan))
            .unwrap();
        assert!(!f.ready().exists());
        assert_eq!(f.load("runtime-a"), expected);
        assert_eq!(f.load("runtime-a"), expected);
        assert!(f.cache.verified.lock().unwrap().is_some());
        let restarted = GraphCache::new(f.temp.path().join("cache"), "phone-a".into());
        assert_eq!(
            restarted
                .load(&f.source, "runtime-a", false, |plan| f.loader(plan))
                .unwrap(),
            expected
        );
        assert!(restarted.verified.lock().unwrap().is_some());
        assert_eq!(f.loads.take(), ["source", "build", "hit", "hit"]);
    }

    #[test]
    fn changed_graph_source_runtime_device_and_manifest_rebuild() {
        let mut f = Fixture::new();
        let first = f.load("runtime-a;cpu");
        f.loads.take();
        for name in [GRAPHS[0], "vocab.txt"] {
            let path = f.ready().join(name);
            let mut bytes = fs::read(&path).unwrap();
            bytes[0] ^= 1;
            fs::write(&path, bytes).unwrap();
            assert_eq!(f.load("runtime-a;cpu"), first);
            assert_eq!(f.loads.take(), ["build"]);
            assert_eq!(
                fs::read(path).unwrap(),
                fs::read(f.source.join(name)).unwrap()
            );
        }

        let source = f.source.join(GRAPHS[0]);
        let mtime = fs::metadata(&source).unwrap().modified().unwrap();
        let mut bytes = fs::read(&source).unwrap();
        bytes[0] ^= 1;
        fs::write(&source, bytes).unwrap();
        File::options()
            .write(true)
            .open(source)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(mtime))
            .unwrap();
        let updated = f.load("runtime-a;cpu");
        assert_ne!(updated, first);
        assert_eq!(f.loads.take(), ["build"]);
        for recipe in ["runtime-b;cpu", "runtime-b;xnnpack"] {
            assert_eq!(f.load(recipe), updated);
            assert_eq!(f.loads.take(), ["build"]);
        }
        f.cache.device = "phone-b".into();
        assert_eq!(f.load("runtime-b;xnnpack"), updated);
        assert_eq!(f.loads.take(), ["build"]);
        fs::write(f.ready().join("manifest.json"), b"{partial").unwrap();
        let abandoned = f.cache.root.join(format!(".build-{}", Uuid::new_v4()));
        fs::create_dir(&abandoned).unwrap();
        fs::write(abandoned.join("partial"), b"incomplete").unwrap();
        fs::write(f.cache.root.join("unrelated"), b"keep").unwrap();
        assert_eq!(f.load("runtime-b;xnnpack"), updated);
        assert_eq!(f.loads.take(), ["build"]);
        assert!(!abandoned.exists());
        assert_eq!(fs::read(f.cache.root.join("unrelated")).unwrap(), b"keep");
        assert_eq!(fs::read_dir(&f.cache.root).unwrap().count(), 3);
    }

    #[test]
    fn missing_original_never_loads_a_surviving_cache() {
        let f = Fixture::new();
        f.load("runtime-a");
        fs::remove_file(f.source.join(GRAPHS[0])).unwrap();
        assert!(
            f.cache
                .load(&f.source, "runtime-a", true, |plan| f.loader(plan))
                .is_err()
        );
        assert_eq!(f.loads.take(), ["build", "source"]);
    }

    #[test]
    fn failed_cache_load_or_serialization_recovers_from_source() {
        for cached in [false, true] {
            let f = Fixture::new();
            let expected = f.loader(LoadPlan::Source { save_to: None }).unwrap();
            if cached {
                assert_eq!(f.load("runtime-a"), expected);
            }
            f.loads.take();
            let mut failed = false;
            let actual = f
                .cache
                .load(&f.source, "runtime-a", true, |plan| match plan {
                    LoadPlan::Cached { .. } if cached => {
                        failed = true;
                        Err(invalid_cache())
                    }
                    LoadPlan::Source { save_to: Some(_) } if !cached => {
                        failed = true;
                        Err(io::Error::new(
                            io::ErrorKind::StorageFull,
                            "injected full disk",
                        ))
                    }
                    _ => f.loader(plan),
                })
                .unwrap();
            assert!(failed);
            assert_eq!(actual, expected);
            assert_eq!(f.loads.take(), [if cached { "build" } else { "source" }]);
            assert_eq!(f.ready().exists(), cached);
            assert_eq!(
                fs::read_dir(&f.cache.root).unwrap().count(),
                if cached { 2 } else { 1 }
            );
        }
    }

    #[test]
    fn busy_or_unusable_cache_never_blocks_source_loading() {
        let f = Fixture::new();
        let expected = f.load("runtime-a");
        let lock = File::options()
            .read(true)
            .write(true)
            .open(f.cache.root.join(".lock"))
            .unwrap();
        lock.try_lock().unwrap();
        assert_eq!(f.load("runtime-a"), expected);
        drop(lock);
        let file = f.temp.path().join("not-a-directory");
        fs::write(&file, b"existing").unwrap();
        let cache = GraphCache::new(file, "phone-a".into());
        assert_eq!(
            cache
                .load(&f.source, "runtime-a", true, |plan| f.loader(plan))
                .unwrap(),
            expected
        );
        assert_eq!(f.loads.take(), ["build", "source", "source"]);
    }

    #[test]
    fn oversized_or_external_output_is_not_published() {
        let f = Fixture::new();
        for oversize in [true, false] {
            let result = f.cache.load(&f.source, "runtime-a", true, |plan| {
                let save_to = match &plan {
                    LoadPlan::Source { save_to } => *save_to,
                    _ => None,
                };
                let result = f.loader(plan)?;
                if let Some(path) = save_to {
                    if oversize {
                        File::options()
                            .write(true)
                            .open(path.join(GRAPHS[0]))?
                            .set_len(MAX_BYTES + 1)?;
                    } else {
                        fs::write(path.join("unverified.weights"), b"external")?;
                    }
                }
                Ok::<_, io::Error>(result)
            });
            assert!(result.is_ok());
            assert!(!f.ready().exists());
        }
    }

    #[cfg(unix)]
    #[test]
    fn ready_symlink_cannot_redirect_loading_or_cleanup() {
        let f = Fixture::new();
        let expected = f.load("runtime-a");
        let outside = f.temp.path().join("outside");
        fs::create_dir(&outside).unwrap();
        fs::write(outside.join("preserve"), b"original").unwrap();
        fs::remove_dir_all(f.ready()).unwrap();
        std::os::unix::fs::symlink(&outside, f.ready()).unwrap();
        assert_eq!(f.load("runtime-a"), expected);
        assert_eq!(f.loads.take(), ["build", "build"]);
        assert_eq!(fs::read(outside.join("preserve")).unwrap(), b"original");
    }
}
