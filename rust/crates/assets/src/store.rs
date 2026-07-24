use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use tokio::sync::Mutex;

use crate::archive;
use crate::download::{self, CancellationToken, DownloadTarget, Downloader, Error, Progress};

const STAGING_DIR: &str = ".staging";
const ARCHIVE_FILE: &str = ".archive.tar.gz";
const EXTRACTION_DIR: &str = ".extracted";

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

impl Asset {
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
    mutation_gate: Mutex<()>,
}

impl AssetStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            downloader: OnceLock::new(),
            mutation_gate: Mutex::new(()),
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

    pub async fn estimated_download_size(&self, asset: &Asset) -> Option<u64> {
        if self.is_downloaded(asset) {
            return Some(0);
        }
        self.downloader()
            .ok()?
            .estimated_download_size(&self.download_targets(asset))
            .await
    }

    pub async fn download(
        &self,
        asset: &Asset,
        mut on_progress: impl FnMut(Progress) + Send,
        cancellation: CancellationToken,
    ) -> Result<(), Error> {
        let _guard = self.mutation_gate.lock().await;
        if self.is_downloaded(asset) {
            return Ok(());
        }
        if cancellation.is_cancelled() {
            return Err(Error::Cancelled);
        }

        let mut last_progress = None;
        self.downloader()?
            .download(
                self.download_targets(asset),
                |mut progress| {
                    progress.complete = false;
                    last_progress = Some(progress.clone());
                    on_progress(progress);
                },
                cancellation.clone(),
            )
            .await?;

        match &asset.kind {
            AssetKind::Files(files) => self.publish_files(asset, files)?,
            AssetKind::TarGz { .. } => self.publish_archive(asset, cancellation).await?,
        }

        if let Some(mut progress) = last_progress {
            progress.percentage = 100.0;
            progress.file_complete = false;
            progress.complete = true;
            on_progress(progress);
        }
        Ok(())
    }

    pub async fn remove(&self, asset: &Asset) -> Result<(), Error> {
        let _guard = self.mutation_gate.lock().await;
        remove_path(&self.asset_dir(asset))?;
        remove_path(&self.staging_dir(asset))?;
        Ok(())
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
        assert_send(store.download(&asset, |_| {}, CancellationToken::default()));
        assert_send(store.estimated_download_size(&asset));
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
    async fn publishes_all_files_before_reporting_completion() {
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
        let mut completion_observed_after_publish = false;
        store
            .download(
                &asset,
                |progress| {
                    if progress.complete {
                        completion_observed_after_publish = final_dir.is_dir();
                    }
                },
                CancellationToken::default(),
            )
            .await
            .unwrap();

        assert!(completion_observed_after_publish);
        assert!(store.is_downloaded(&asset));
        assert_eq!(fs::read(final_dir.join("model.onnx")).unwrap(), b"model");
        assert_eq!(fs::read(final_dir.join("vocab.txt")).unwrap(), b"vocab");
        assert!(!store.staging_dir(&asset).exists());
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
            .download(&asset, |_| {}, CancellationToken::default())
            .await
            .unwrap();

        let directory = store.asset_dir(&asset);
        fs::write(directory.join("libonnxruntime.dylib"), b"derived").unwrap();
        assert!(store.is_downloaded(&asset));

        fs::remove_file(directory.join("runtime.tgz")).unwrap();
        assert!(!store.is_downloaded(&asset));
        stage_files(&store, &asset, &[("runtime.tgz", b"archive")]);
        store
            .download(&asset, |_| {}, CancellationToken::default())
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
            .download(&asset, |_| {}, CancellationToken::default())
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
                .download(&asset, |_| {}, CancellationToken::default())
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
