use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

use futures_util::future::join_all;
use tokio::sync::{Mutex, Semaphore};

use crate::archive;
use crate::download::{self, CancellationToken, DownloadTarget, Downloader, Error, Progress};

const STAGING_DIR: &str = ".staging";
const ARCHIVE_FILE: &str = ".archive.tar.gz";
const EXTRACTION_DIR: &str = ".extracted";
const ASSET_CONCURRENCY: usize = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Asset {
    components: Vec<String>,
    kind: AssetKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum AssetKind {
    Files(Vec<AssetFile>),
    TarGz { url: String, sha256: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssetFile {
    pub name: String,
    pub url: String,
    pub sha256: String,
}

#[derive(Debug, Clone)]
pub struct AssetDownloadProgress {
    pub asset_progress: Progress,
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub percentage: f64,
}

#[derive(Debug, thiserror::Error)]
pub enum AssetStoreError {
    #[error(transparent)]
    Download(#[from] Error),
    #[error("asset is busy")]
    Busy,
}

impl Asset {
    pub fn file(components: Vec<String>, file: AssetFile) -> Result<Self, Error> {
        Self::files(components, vec![file])
    }

    pub fn files(components: Vec<String>, files: Vec<AssetFile>) -> Result<Self, Error> {
        validate_components(&components)?;
        if files.is_empty() {
            return Err(Error::InvalidTarget("asset has no files".to_string()));
        }
        let mut names = HashSet::new();
        for file in &files {
            validate_component(&file.name)?;
            download::validate_sha256(&file.sha256)?;
            if !names.insert(file.name.as_str()) {
                return Err(Error::InvalidTarget(format!(
                    "asset has a duplicate file name {}",
                    file.name
                )));
            }
        }
        Ok(Self {
            components,
            kind: AssetKind::Files(files),
        })
    }

    pub fn tar_gz(components: Vec<String>, url: String, sha256: String) -> Result<Self, Error> {
        validate_components(&components)?;
        download::validate_sha256(&sha256)?;
        Ok(Self {
            components,
            kind: AssetKind::TarGz { url, sha256 },
        })
    }
}

pub struct AssetStore {
    root: PathBuf,
    downloader: OnceLock<Downloader>,
    asset_locks: std::sync::Mutex<HashMap<Vec<String>, Arc<Mutex<()>>>>,
    asset_slots: Semaphore,
}

impl AssetStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            downloader: OnceLock::new(),
            asset_locks: std::sync::Mutex::new(HashMap::new()),
            asset_slots: Semaphore::new(ASSET_CONCURRENCY),
        }
    }

    pub fn asset_dir(&self, asset: &Asset) -> PathBuf {
        join_components(&self.root, &asset.components)
    }

    pub fn file_path(&self, asset: &Asset, name: &str) -> Option<PathBuf> {
        match &asset.kind {
            AssetKind::Files(files) if files.iter().any(|file| file.name == name) => {
                Some(self.asset_dir(asset).join(name))
            }
            _ => None,
        }
    }

    pub fn is_downloaded(&self, asset: &Asset) -> bool {
        let directory = self.asset_dir(asset);
        match &asset.kind {
            AssetKind::Files(files) => files
                .iter()
                .all(|file| is_regular_file(&directory.join(&file.name))),
            AssetKind::TarGz { .. } => is_directory(&directory),
        }
    }

    pub async fn estimated_download_size(&self, assets: &[Asset]) -> Option<u64> {
        let mut total = 0u64;
        for asset in assets {
            if self.is_downloaded(asset) {
                continue;
            }
            total = total.checked_add(
                self.downloader()
                    .ok()?
                    .estimated_download_size(&self.download_targets(asset))
                    .await?,
            )?;
        }
        Some(total)
    }

    pub async fn download(
        &self,
        assets: &[Asset],
        on_progress: impl FnMut(AssetDownloadProgress) + Send,
        cancellation: CancellationToken,
    ) -> Result<(), Error> {
        if cancellation.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let mut keys = HashSet::new();
        for asset in assets {
            if !keys.insert(&asset.components) {
                return Err(Error::InvalidTarget(format!(
                    "duplicate asset key {}",
                    asset.components.join("/")
                )));
            }
        }

        let locks = assets
            .iter()
            .map(|asset| self.asset_lock(asset))
            .collect::<Result<Vec<_>, _>>()?;
        let progress = std::sync::Mutex::new(BatchProgress::new(assets.len(), on_progress));
        let jobs = assets
            .iter()
            .zip(locks)
            .enumerate()
            .map(|(asset_index, (asset, lock))| {
                self.download_asset(asset_index, asset, lock, &progress, cancellation.clone())
            });
        let results = join_all(jobs).await;
        if cancellation.is_cancelled() {
            return Err(Error::Cancelled);
        }
        if let Some(error) = results.into_iter().find_map(Result::err) {
            return Err(error);
        }
        Ok(())
    }

    pub async fn remove(&self, asset: &Asset) -> Result<(), AssetStoreError> {
        let lock = self.asset_lock(asset)?;
        let _guard = lock.try_lock().map_err(|_| AssetStoreError::Busy)?;
        remove_path(&self.asset_dir(asset))?;
        remove_path(&self.staging_dir(asset))?;
        Ok(())
    }

    async fn download_asset<F>(
        &self,
        asset_index: usize,
        asset: &Asset,
        lock: Arc<Mutex<()>>,
        progress: &std::sync::Mutex<BatchProgress<F>>,
        cancellation: CancellationToken,
    ) -> Result<(), Error>
    where
        F: FnMut(AssetDownloadProgress) + Send,
    {
        let _guard = tokio::select! {
            guard = lock.lock() => guard,
            _ = cancellation.cancelled() => return Err(Error::Cancelled),
        };
        if self.is_downloaded(asset) {
            progress.lock().expect("progress lock").skip(asset_index);
            return Ok(());
        }
        let _slot = tokio::select! {
            slot = self.asset_slots.acquire() => slot.expect("asset semaphore closed"),
            _ = cancellation.cancelled() => return Err(Error::Cancelled),
        };

        self.downloader()?
            .download(
                self.download_targets(asset),
                |mut update| {
                    update.complete = false;
                    progress
                        .lock()
                        .expect("progress lock")
                        .update(asset_index, update);
                },
                cancellation.clone(),
            )
            .await?;
        match &asset.kind {
            AssetKind::Files(files) => self.publish_files(asset, files)?,
            AssetKind::TarGz { .. } => self.publish_archive(asset, cancellation).await?,
        }
        Ok(())
    }

    fn asset_lock(&self, asset: &Asset) -> Result<Arc<Mutex<()>>, Error> {
        let mut locks = self.asset_locks.lock().expect("asset lock registry");
        if let Some((key, lock)) = locks
            .iter()
            .find(|(key, _)| keys_overlap(key, &asset.components))
        {
            if *key == asset.components {
                return Ok(Arc::clone(lock));
            }
            return Err(Error::InvalidTarget(format!(
                "asset keys {} and {} overlap",
                key.join("/"),
                asset.components.join("/")
            )));
        }
        let lock = Arc::new(Mutex::new(()));
        locks.insert(asset.components.clone(), Arc::clone(&lock));
        Ok(lock)
    }

    fn downloader(&self) -> Result<&Downloader, Error> {
        if let Some(downloader) = self.downloader.get() {
            return Ok(downloader);
        }
        let downloader = Downloader::new()?;
        Ok(self.downloader.get_or_init(|| downloader))
    }

    fn staging_dir(&self, asset: &Asset) -> PathBuf {
        join_components(&self.root.join(STAGING_DIR), &asset.components)
    }

    fn download_targets(&self, asset: &Asset) -> Vec<DownloadTarget> {
        let staging = self.staging_dir(asset);
        match &asset.kind {
            AssetKind::Files(files) => files
                .iter()
                .map(|file| DownloadTarget {
                    label: file.name.clone(),
                    url: file.url.clone(),
                    sha256: file.sha256.clone(),
                    destination: staging.join(&file.name),
                })
                .collect(),
            AssetKind::TarGz { url, sha256 } => vec![DownloadTarget {
                label: asset.components.last().cloned().unwrap_or_default(),
                url: url.clone(),
                sha256: sha256.clone(),
                destination: staging.join(ARCHIVE_FILE),
            }],
        }
    }

    fn publish_files(&self, asset: &Asset, files: &[AssetFile]) -> Result<(), Error> {
        let staging = self.staging_dir(asset);
        for file in files {
            if !is_regular_file(&staging.join(&file.name)) {
                return Err(Error::Validation(format!(
                    "{} is not a regular file",
                    staging.join(&file.name).display()
                )));
            }
        }
        let expected = files
            .iter()
            .map(|file| file.name.as_str())
            .collect::<HashSet<_>>();
        for entry in fs::read_dir(&staging)? {
            let entry = entry?;
            let name = entry.file_name();
            if name.to_str().is_some_and(|name| expected.contains(name)) {
                if !is_regular_file(&entry.path()) {
                    return Err(Error::Validation(format!(
                        "{} is not a regular file",
                        entry.path().display()
                    )));
                }
            } else {
                remove_path(&entry.path())?;
            }
        }
        self.publish_directory(&staging, &self.asset_dir(asset))
    }

    async fn publish_archive(
        &self,
        asset: &Asset,
        cancellation: CancellationToken,
    ) -> Result<(), Error> {
        let staging = self.staging_dir(asset);
        let archive_path = staging.join(ARCHIVE_FILE);
        let extraction_dir = staging.join(EXTRACTION_DIR);
        let extraction_for_task = extraction_dir.clone();
        let extraction_cancellation = cancellation.clone();
        let source = tokio::task::spawn_blocking(move || {
            let result = archive::extract_tar_gz(
                &archive_path,
                &extraction_for_task,
                &extraction_cancellation,
            );
            if result.is_err() {
                let _ = fs::remove_dir_all(&extraction_for_task);
            }
            result
        })
        .await
        .map_err(|error| Error::Io(std::io::Error::other(error)))??;
        if cancellation.is_cancelled() {
            remove_path(&extraction_dir)?;
            return Err(Error::Cancelled);
        }
        self.publish_directory(&source, &self.asset_dir(asset))?;
        remove_path(&staging)?;
        Ok(())
    }

    fn publish_directory(&self, source: &Path, destination: &Path) -> Result<(), Error> {
        let parent = destination
            .parent()
            .ok_or_else(|| Error::InvalidTarget(destination.display().to_string()))?;
        fs::create_dir_all(parent)?;
        remove_path(destination)?;
        fs::rename(source, destination)?;
        Ok(())
    }
}

struct BatchProgress<F> {
    assets: Vec<Option<Progress>>,
    pending: Vec<bool>,
    callback: F,
}

impl<F> BatchProgress<F>
where
    F: FnMut(AssetDownloadProgress),
{
    fn new(asset_count: usize, callback: F) -> Self {
        Self {
            assets: vec![None; asset_count],
            pending: vec![true; asset_count],
            callback,
        }
    }

    fn skip(&mut self, asset_index: usize) {
        self.pending[asset_index] = false;
    }

    fn update(&mut self, asset_index: usize, asset_progress: Progress) {
        self.pending[asset_index] = false;
        self.assets[asset_index] = Some(asset_progress.clone());
        self.emit(asset_progress);
    }

    fn emit(&mut self, asset_progress: Progress) {
        let downloaded_bytes = self
            .assets
            .iter()
            .flatten()
            .map(|progress| progress.downloaded_bytes)
            .sum();
        let total_bytes = (!self.pending.iter().any(|pending| *pending))
            .then(|| {
                self.assets
                    .iter()
                    .flatten()
                    .map(|progress| progress.total_bytes)
                    .try_fold(0u64, |total, value| total.checked_add(value?))
            })
            .flatten();
        let percentage = total_bytes
            .filter(|total| *total > 0)
            .map(|total| ((downloaded_bytes as f64 / total as f64) * 100.0).clamp(0.0, 100.0))
            .unwrap_or(0.0);
        (self.callback)(AssetDownloadProgress {
            asset_progress,
            downloaded_bytes,
            total_bytes,
            percentage,
        });
    }
}

fn keys_overlap(left: &[String], right: &[String]) -> bool {
    left.starts_with(right) || right.starts_with(left)
}

fn validate_components(components: &[String]) -> Result<(), Error> {
    if components.is_empty() {
        return Err(Error::InvalidTarget(
            "asset key has no components".to_string(),
        ));
    }
    for component in components {
        validate_component(component)?;
    }
    if components[0] == STAGING_DIR {
        return Err(Error::InvalidTarget(format!("'{STAGING_DIR}' is reserved")));
    }
    Ok(())
}

fn validate_component(component: &str) -> Result<(), Error> {
    if !component.is_empty()
        && component != "."
        && component != ".."
        && !component.contains('/')
        && !component.contains('\\')
    {
        return Ok(());
    }
    Err(Error::InvalidTarget(format!(
        "'{component}' is not a safe path component"
    )))
}

fn join_components(root: &Path, components: &[String]) -> PathBuf {
    components
        .iter()
        .fold(root.to_path_buf(), |path, component| path.join(component))
}

fn is_regular_file(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_file())
        .unwrap_or(false)
}

fn is_directory(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_dir())
        .unwrap_or(false)
}

fn remove_path(path: &Path) -> Result<(), Error> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    if metadata.file_type().is_dir() {
        fs::remove_dir_all(path)?;
    } else {
        fs::remove_file(path)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;
    use std::time::{SystemTime, UNIX_EPOCH};

    use flate2::Compression;
    use flate2::write::GzEncoder;
    use sha2::{Digest, Sha256};
    use tar::{Builder, EntryType, Header};

    use super::*;

    #[test]
    fn store_and_operations_are_send_and_sync() {
        fn assert_send<T: Send>(_: T) {}
        fn assert_send_sync<T: Send + Sync>() {}

        assert_send_sync::<AssetStore>();
        assert_send_sync::<CancellationToken>();

        let store = AssetStore::new("assets");
        let asset =
            Asset::files(key(&["models", "clip"]), vec![file("model.onnx", b"model")]).unwrap();
        assert_send(store.download(
            std::slice::from_ref(&asset),
            |_| {},
            CancellationToken::default(),
        ));
        assert_send(store.estimated_download_size(std::slice::from_ref(&asset)));
        assert_send(store.remove(&asset));
    }

    #[test]
    fn rejects_invalid_assets() {
        assert!(Asset::files(Vec::new(), vec![file("model", b"model")]).is_err());
        assert!(Asset::files(key(&[".staging", "model"]), vec![file("model", b"model")]).is_err());
        assert!(Asset::files(key(&["models", ".."]), vec![file("model", b"model")]).is_err());
        assert!(Asset::files(key(&["models", "model"]), Vec::new()).is_err());
        assert!(
            Asset::files(
                key(&["models", "model"]),
                vec![file("model", b"a"), file("model", b"b")]
            )
            .is_err()
        );
        let mut invalid_sha = file("model", b"model");
        invalid_sha.sha256 = "invalid".to_string();
        assert!(Asset::files(key(&["models", "model"]), vec![invalid_sha]).is_err());
    }

    #[tokio::test]
    async fn publishes_all_files() {
        let root = scratch_dir("files");
        let store = AssetStore::new(&root);
        let asset = Asset::files(
            key(&["models", "clip"]),
            vec![file("model.onnx", b"model"), file("vocab.txt", b"vocab")],
        )
        .unwrap();
        stage_files(
            &store,
            &asset,
            &[("model.onnx", b"model"), ("vocab.txt", b"vocab")],
        );

        let final_dir = store.asset_dir(&asset);
        store
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                CancellationToken::default(),
            )
            .await
            .unwrap();

        assert!(store.is_downloaded(&asset));
        assert_eq!(fs::read(final_dir.join("model.onnx")).unwrap(), b"model");
        assert_eq!(fs::read(final_dir.join("vocab.txt")).unwrap(), b"vocab");
        assert!(!store.staging_dir(&asset).exists());
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn aggregates_progress_across_assets() {
        let root = scratch_dir("batch");
        let store = AssetStore::new(&root);
        let first = Asset::files(key(&["models", "first"]), vec![file("model", b"first")]).unwrap();
        let second =
            Asset::files(key(&["models", "second"]), vec![file("model", b"second")]).unwrap();
        stage_files(&store, &first, &[("model", b"first")]);
        stage_files(&store, &second, &[("model", b"second")]);
        let mut latest_progress = None;

        store
            .download(
                &[first.clone(), second.clone()],
                |progress| {
                    latest_progress = Some((
                        progress.downloaded_bytes,
                        progress.total_bytes,
                        progress.percentage,
                    ));
                },
                CancellationToken::default(),
            )
            .await
            .unwrap();

        assert!(store.is_downloaded(&first));
        assert!(store.is_downloaded(&second));
        assert_eq!(latest_progress, Some((11, Some(11), 100.0)));
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn publishes_successful_assets_when_a_sibling_fails() {
        let root = scratch_dir("batch-failure");
        let store = AssetStore::new(&root);
        let good = Asset::files(key(&["models", "good"]), vec![file("model", b"good")]).unwrap();
        let mut bad_file = file("model", b"bad");
        bad_file.url = ":".to_string();
        let bad = Asset::files(key(&["models", "bad"]), vec![bad_file]).unwrap();
        stage_files(&store, &good, &[("model", b"good")]);

        store
            .download(
                &[good.clone(), bad.clone()],
                |_| {},
                CancellationToken::default(),
            )
            .await
            .unwrap_err();

        assert!(store.is_downloaded(&good));
        assert!(!store.is_downloaded(&bad));
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn asset_locks_are_keyed_and_cancellable() {
        let root = scratch_dir("locks");
        let store = Arc::new(AssetStore::new(&root));
        let asset = Asset::files(key(&["models", "same"]), vec![file("model", b"model")]).unwrap();
        assert!(matches!(
            store
                .download(
                    &[asset.clone(), asset.clone()],
                    |_| {},
                    CancellationToken::default()
                )
                .await,
            Err(Error::InvalidTarget(_))
        ));
        let lock = store.asset_lock(&asset).unwrap();
        let guard = lock.lock().await;
        assert!(matches!(
            store.remove(&asset).await,
            Err(AssetStoreError::Busy)
        ));

        let token = CancellationToken::new();
        let cancellation = token.clone();
        let waiting_store = Arc::clone(&store);
        let waiting_asset = asset.clone();
        let waiter = tokio::spawn(async move {
            waiting_store
                .download(&[waiting_asset], |_| {}, token)
                .await
        });
        tokio::task::yield_now().await;
        cancellation.cancel();
        assert!(matches!(waiter.await.unwrap(), Err(Error::Cancelled)));
        drop(guard);

        stage_files(&store, &asset, &[("model", b"model")]);
        let first_assets = [asset.clone()];
        let second_assets = [asset.clone()];
        let (first, second) = tokio::join!(
            store.download(&first_assets, |_| {}, CancellationToken::default()),
            store.download(&second_assets, |_| {}, CancellationToken::default())
        );
        first.unwrap();
        second.unwrap();
        assert!(store.is_downloaded(&asset));

        let nested = Asset::files(
            key(&["models", "same", "nested"]),
            vec![file("model", b"model")],
        )
        .unwrap();
        assert!(store.asset_lock(&nested).is_err());
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn ignores_derived_files_and_discards_them_when_rebuilding() {
        let root = scratch_dir("derived");
        let store = AssetStore::new(&root);
        let asset = Asset::files(
            key(&["onnx-runtime", "macos"]),
            vec![file("runtime.tgz", b"archive")],
        )
        .unwrap();
        stage_files(&store, &asset, &[("runtime.tgz", b"archive")]);
        store
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                CancellationToken::default(),
            )
            .await
            .unwrap();

        let directory = store.asset_dir(&asset);
        fs::write(directory.join("libonnxruntime.dylib"), b"derived").unwrap();
        assert!(store.is_downloaded(&asset));

        fs::remove_file(directory.join("runtime.tgz")).unwrap();
        assert!(!store.is_downloaded(&asset));
        stage_files(&store, &asset, &[("runtime.tgz", b"archive")]);
        store
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                CancellationToken::default(),
            )
            .await
            .unwrap();

        assert!(!directory.join("libonnxruntime.dylib").exists());
        assert!(store.is_downloaded(&asset));
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn extracts_and_publishes_tar_gz() {
        let root = scratch_dir("archive");
        let store = AssetStore::new(&root);
        let archive = tar_gz(
            "parakeet",
            &[("encoder.onnx", b"encoder"), ("tokens.txt", b"tokens")],
        );
        let asset = Asset::tar_gz(
            key(&["models", "parakeet"]),
            "https://example.invalid/parakeet.tar.gz".to_string(),
            sha(&archive),
        )
        .unwrap();
        let staging = store.staging_dir(&asset);
        fs::create_dir_all(&staging).unwrap();
        fs::write(staging.join(ARCHIVE_FILE), archive).unwrap();

        store
            .download(
                std::slice::from_ref(&asset),
                |_| {},
                CancellationToken::default(),
            )
            .await
            .unwrap();

        let directory = store.asset_dir(&asset);
        assert_eq!(
            fs::read(directory.join("encoder.onnx")).unwrap(),
            b"encoder"
        );
        assert_eq!(fs::read(directory.join("tokens.txt")).unwrap(), b"tokens");
        assert!(!staging.exists());
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn rejects_tar_links_without_publishing() {
        let root = scratch_dir("archive-link");
        let store = AssetStore::new(&root);
        let archive = tar_gz_with_link();
        let asset = Asset::tar_gz(
            key(&["models", "linked"]),
            "https://example.invalid/linked.tar.gz".to_string(),
            sha(&archive),
        )
        .unwrap();
        let staging = store.staging_dir(&asset);
        fs::create_dir_all(&staging).unwrap();
        fs::write(staging.join(ARCHIVE_FILE), archive).unwrap();

        assert!(
            store
                .download(
                    std::slice::from_ref(&asset),
                    |_| {},
                    CancellationToken::default(),
                )
                .await
                .is_err()
        );
        assert!(!store.asset_dir(&asset).exists());
        assert!(staging.join(ARCHIVE_FILE).is_file());
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn remove_deletes_published_and_staged_data() {
        let root = scratch_dir("remove");
        let store = AssetStore::new(&root);
        let asset =
            Asset::files(key(&["models", "clip"]), vec![file("model.onnx", b"model")]).unwrap();
        let final_dir = store.asset_dir(&asset);
        let staging = store.staging_dir(&asset);
        fs::create_dir_all(&final_dir).unwrap();
        fs::write(final_dir.join("model.onnx"), b"model").unwrap();
        fs::create_dir_all(&staging).unwrap();
        fs::write(staging.join("model.onnx.tmp"), b"partial").unwrap();

        store.remove(&asset).await.unwrap();
        assert!(!final_dir.exists());
        assert!(!staging.exists());
        store.remove(&asset).await.unwrap();
        let _ = fs::remove_dir_all(root);
    }

    fn key(components: &[&str]) -> Vec<String> {
        components
            .iter()
            .map(|component| component.to_string())
            .collect()
    }

    fn file(name: &str, bytes: &[u8]) -> AssetFile {
        AssetFile {
            name: name.to_string(),
            url: format!("https://example.invalid/{name}"),
            sha256: sha(bytes),
        }
    }

    fn stage_files(store: &AssetStore, asset: &Asset, files: &[(&str, &[u8])]) {
        let directory = store.staging_dir(asset);
        fs::create_dir_all(&directory).unwrap();
        for (name, bytes) in files {
            fs::write(directory.join(name), bytes).unwrap();
        }
    }

    fn sha(bytes: &[u8]) -> String {
        Sha256::digest(bytes)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }

    fn tar_gz(root: &str, files: &[(&str, &[u8])]) -> Vec<u8> {
        let mut bytes = Vec::new();
        {
            let encoder = GzEncoder::new(&mut bytes, Compression::default());
            let mut archive = Builder::new(encoder);
            for (name, contents) in files {
                let mut header = Header::new_gnu();
                header.set_size(contents.len() as u64);
                header.set_mode(0o644);
                header.set_cksum();
                archive
                    .append_data(
                        &mut header,
                        format!("{root}/{name}"),
                        Cursor::new(*contents),
                    )
                    .unwrap();
            }
            archive.into_inner().unwrap().finish().unwrap();
        }
        bytes
    }

    fn tar_gz_with_link() -> Vec<u8> {
        let mut bytes = Vec::new();
        {
            let encoder = GzEncoder::new(&mut bytes, Compression::default());
            let mut archive = Builder::new(encoder);
            let mut header = Header::new_gnu();
            header.set_entry_type(EntryType::Symlink);
            header.set_size(0);
            header.set_mode(0o777);
            header.set_link_name("../outside").unwrap();
            header.set_cksum();
            archive
                .append_data(&mut header, "model/link", Cursor::new(Vec::<u8>::new()))
                .unwrap();
            archive.into_inner().unwrap().finish().unwrap();
        }
        bytes
    }

    fn scratch_dir(name: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("ente-assets-{name}-{suffix}"))
    }
}
