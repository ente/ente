use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock, PoisonError};

use tokio::runtime::Builder;

use crate::archive;
use crate::download::{self, Progress, Target};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModelTarget {
    Files {
        id: String,
        files: Vec<ModelFile>,
    },
    TarGz {
        id: String,
        url: String,
        sha256: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelFile {
    pub name: String,
    pub url: String,
    pub sha256: String,
}

#[derive(Debug, Clone)]
pub struct ModelDownloadProgress {
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub percent: i32,
    pub status: String,
    pub log_line: Option<String>,
}

pub struct ModelDownloader {
    downloader: OnceLock<download::Downloader>,
    models_dir: PathBuf,
    active: AtomicBool,
    download_lock: Mutex<()>,
}

impl ModelDownloader {
    pub fn new(models_dir: impl Into<PathBuf>) -> Self {
        Self {
            downloader: OnceLock::new(),
            models_dir: models_dir.into(),
            active: AtomicBool::new(false),
            download_lock: Mutex::new(()),
        }
    }

    pub fn downloader(&self) -> Result<&download::Downloader, download::Error> {
        if let Some(downloader) = self.downloader.get() {
            return Ok(downloader);
        }
        let downloader = download::Downloader::new()?;
        Ok(self.downloader.get_or_init(|| downloader))
    }

    pub fn model_dir(&self, target: &ModelTarget) -> PathBuf {
        storage_dir(&self.models_dir, target)
    }

    pub fn file_path(&self, target: &ModelTarget, name: &str) -> Option<PathBuf> {
        match target {
            ModelTarget::Files { files, .. } if files.iter().any(|file| file.name == name) => {
                Some(storage_dir(&self.models_dir, target).join(name))
            }
            _ => None,
        }
    }

    pub fn is_downloaded(&self, target: &ModelTarget) -> bool {
        if let ModelTarget::TarGz { .. } = target {
            return storage_dir(&self.models_dir, target).is_dir();
        }
        let paths = expected_paths(&self.models_dir, target);
        !paths.is_empty() && paths.iter().all(|path| path.is_file())
    }

    pub fn is_download_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }

    pub fn remove_downloaded(&self, target: &ModelTarget) -> bool {
        let Ok(_guard) = self.download_lock.try_lock() else {
            return false;
        };
        if checked_file_name(storage_key(target)).is_err() {
            return false;
        }
        let dir = storage_dir(&self.models_dir, target);
        dir.exists() && fs::remove_dir_all(dir).is_ok()
    }

    pub fn download(
        &self,
        targets: &[ModelTarget],
        mut on_progress: impl FnMut(ModelDownloadProgress),
        cancellation: &download::CancellationToken,
    ) -> Result<(), download::Error> {
        let _guard = self
            .download_lock
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let pending = targets
            .iter()
            .filter(|target| !self.is_downloaded(target))
            .collect::<Vec<_>>();
        if pending.is_empty() {
            return Ok(());
        }

        let mut transfers = Vec::new();
        for target in &pending {
            transfers.extend(download_targets(&self.models_dir, target)?);
        }

        if cancellation.is_cancelled() {
            return Err(download::Error::Cancelled);
        }
        let downloader = self.downloader()?;
        self.active.store(true, Ordering::SeqCst);
        let result = download::fetch(
            downloader,
            transfers,
            |progress| on_progress(display_progress(progress)),
            || cancellation.is_cancelled(),
        )
        .and_then(|()| {
            for target in &pending {
                if cancellation.is_cancelled() {
                    return Err(download::Error::Cancelled);
                }
                self.extract_if_archive(target, &mut on_progress)?;
            }
            Ok(())
        });
        self.active.store(false, Ordering::SeqCst);
        result
    }

    fn extract_if_archive(
        &self,
        target: &ModelTarget,
        on_progress: &mut impl FnMut(ModelDownloadProgress),
    ) -> Result<(), download::Error> {
        let ModelTarget::TarGz { id, .. } = target else {
            return Ok(());
        };
        on_progress(ModelDownloadProgress {
            downloaded_bytes: 0,
            total_bytes: None,
            percent: 99,
            status: "Extracting...".to_string(),
            log_line: Some(format!("Extracting model archive id={id}")),
        });
        let archive_path = self.staging_dir().join(format!("{id}.tar.gz"));
        let extraction_dir = self.staging_dir().join(id);
        let result =
            archive::extract_tar_gz(&archive_path, &extraction_dir, &self.model_dir(target));
        if result.is_err() {
            let _ = fs::remove_dir_all(extraction_dir);
        } else {
            let _ = fs::remove_file(&archive_path);
        }
        result
    }

    fn staging_dir(&self) -> PathBuf {
        self.models_dir.join(".staging")
    }

    pub fn estimated_download_size(&self, target: &ModelTarget) -> Option<u64> {
        let runtime = Builder::new_current_thread()
            .enable_io()
            .enable_time()
            .build()
            .ok()?;
        let downloader = self.downloader().ok()?;
        runtime.block_on(async {
            let mut total: u64 = 0;
            let mut any = false;
            for entry in download_targets(&self.models_dir, target).ok()? {
                let path = &entry.destination;
                let size = if path.exists() {
                    fs::metadata(path).ok().map(|m| m.len()).filter(|s| *s > 0)
                } else {
                    download::probe_content_length(downloader.client(), &entry.url).await
                };
                if let Some(size) = size {
                    any = true;
                    total = total.saturating_add(size);
                }
            }
            any.then_some(total)
        })
    }
}

fn storage_key(target: &ModelTarget) -> &str {
    match target {
        ModelTarget::Files { id, .. } | ModelTarget::TarGz { id, .. } => id,
    }
}

fn storage_dir(models_dir: &Path, target: &ModelTarget) -> PathBuf {
    models_dir.join(storage_key(target))
}

fn expected_paths(models_dir: &Path, target: &ModelTarget) -> Vec<PathBuf> {
    let dir = storage_dir(models_dir, target);
    match target {
        ModelTarget::TarGz { .. } => vec![dir],
        ModelTarget::Files { files, .. } => files.iter().map(|file| dir.join(&file.name)).collect(),
    }
}

fn download_targets(
    models_dir: &Path,
    target: &ModelTarget,
) -> Result<Vec<Target>, download::Error> {
    let dir = storage_dir(models_dir, target);
    match target {
        ModelTarget::TarGz { id, url, sha256 } => {
            checked_file_name(id)?;
            Ok(vec![Target {
                label: "Model".to_string(),
                url: url.clone(),
                sha256: sha256.clone(),
                destination: models_dir.join(".staging").join(format!("{id}.tar.gz")),
            }])
        }
        ModelTarget::Files { id, files } => {
            checked_file_name(id)?;
            if files.is_empty() {
                return Err(download::Error::InvalidTarget(format!("{id} has no files")));
            }
            let mut names = HashSet::new();
            files
                .iter()
                .map(|file| {
                    checked_file_name(&file.name)?;
                    if !names.insert(file.name.as_str()) {
                        return Err(download::Error::InvalidTarget(format!(
                            "{id} has a duplicate file name {}",
                            file.name
                        )));
                    }
                    Ok(Target {
                        label: file.name.clone(),
                        url: file.url.clone(),
                        sha256: file.sha256.clone(),
                        destination: dir.join(&file.name),
                    })
                })
                .collect()
        }
    }
}

fn checked_file_name(name: &str) -> Result<(), download::Error> {
    if !name.is_empty()
        && name != "."
        && name != ".."
        && !name.contains('/')
        && !name.contains('\\')
    {
        return Ok(());
    }
    Err(download::Error::InvalidTarget(format!(
        "'{name}' is not a safe file name"
    )))
}

fn display_progress(progress: Progress) -> ModelDownloadProgress {
    let total = progress.total_bytes.filter(|total| *total > 0);
    let percent = total
        .map(|total| ((progress.downloaded_bytes * 100 / total) as i32).clamp(0, 99))
        .unwrap_or(0);
    let status = if let Some(total) = total {
        format!(
            "Downloading... {} / {}",
            format_bytes(progress.downloaded_bytes),
            format_bytes(total)
        )
    } else if progress.file_downloaded_bytes > 0 {
        format!(
            "Downloading {}... {}",
            progress.label.to_lowercase(),
            format_bytes(progress.file_downloaded_bytes)
        )
    } else {
        format!("Downloading {}...", progress.label.to_lowercase())
    };
    let log_line = if progress.file_complete {
        Some(format!(
            "Model download file complete label={} bytes={} elapsedMs={} rate={}/s retries={}",
            progress.label,
            progress.file_downloaded_bytes,
            progress.file_elapsed_ms,
            format_bytes(rate_bytes(progress.file_bytes_per_second)),
            progress.file_retry_count
        ))
    } else if progress.complete {
        Some(format!(
            "Model download complete bytes={} elapsedMs={} rate={}/s retries={}",
            progress.downloaded_bytes,
            progress.elapsed_ms,
            format_bytes(rate_bytes(progress.bytes_per_second)),
            progress.retry_count
        ))
    } else {
        None
    };

    ModelDownloadProgress {
        downloaded_bytes: progress.downloaded_bytes,
        total_bytes: progress.total_bytes,
        percent,
        status,
        log_line,
    }
}

fn rate_bytes(bytes_per_second: f64) -> u64 {
    if bytes_per_second.is_finite() && bytes_per_second > 0.0 {
        bytes_per_second as u64
    } else {
        0
    }
}

fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KB", "MB", "GB"];
    let mut size = bytes as f64;
    let mut unit = 0;
    while size >= 1024.0 && unit < UNITS.len() - 1 {
        size /= 1024.0;
        unit += 1;
    }
    format!("{size:.1} {}", UNITS[unit])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ente-model-download-{name}-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).expect("create test dir");
        dir
    }

    fn test_sha() -> String {
        "0".repeat(64)
    }

    fn target(id: &str) -> ModelTarget {
        ModelTarget::Files {
            id: id.to_string(),
            files: vec![
                ModelFile {
                    name: "model.gguf".to_string(),
                    url: "https://example.org/models/main.gguf?download=true".to_string(),
                    sha256: test_sha(),
                },
                ModelFile {
                    name: "mmproj.gguf".to_string(),
                    url: "https://example.org/models/mmproj.gguf".to_string(),
                    sha256: test_sha(),
                },
            ],
        }
    }

    fn write_gguf(path: &Path, content: &[u8]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    #[test]
    fn paths_are_keyed_by_preset_id() {
        let dir = scratch_dir("paths");
        let downloader = ModelDownloader::new(&dir);

        assert_eq!(
            downloader
                .file_path(&target("qwen-2b-q8"), "model.gguf")
                .unwrap(),
            dir.join("qwen-2b-q8/model.gguf")
        );
        assert_eq!(
            downloader.file_path(&target("qwen-2b-q8"), "mmproj.gguf"),
            Some(dir.join("qwen-2b-q8/mmproj.gguf"))
        );

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn is_downloaded_requires_every_member_file() {
        let dir = scratch_dir("is-downloaded");
        let downloader = ModelDownloader::new(&dir);
        let target = target("qwen-2b-q8");
        let model = downloader.file_path(&target, "model.gguf").unwrap();
        let mmproj = downloader.file_path(&target, "mmproj.gguf").unwrap();

        assert!(!downloader.is_downloaded(&target));

        write_gguf(&model, b"GGUFdata");
        assert!(!downloader.is_downloaded(&target));

        write_gguf(&mmproj, b"GGUFdata");
        assert!(downloader.is_downloaded(&target));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn download_skips_when_already_present() {
        let dir = scratch_dir("skip");
        let downloader = ModelDownloader::new(&dir);
        let target = target("qwen-2b-q8");
        write_gguf(
            &downloader.file_path(&target, "model.gguf").unwrap(),
            b"GGUFdata",
        );
        write_gguf(
            &downloader.file_path(&target, "mmproj.gguf").unwrap(),
            b"GGUFdata",
        );

        downloader
            .download(
                std::slice::from_ref(&target),
                |_| {},
                &download::CancellationToken::new(),
            )
            .expect("skip without network");

        let _ = fs::remove_dir_all(dir);
    }

    fn tar_gz_target(id: &str) -> ModelTarget {
        ModelTarget::TarGz {
            id: id.to_string(),
            url: format!("https://models.example.org/{id}.tar.gz"),
            sha256: test_sha(),
        }
    }

    fn file_target(id: &str) -> ModelTarget {
        ModelTarget::Files {
            id: id.to_string(),
            files: vec![ModelFile {
                name: "model.onnx".to_string(),
                url: format!("https://models.example.org/{id}.onnx"),
                sha256: test_sha(),
            }],
        }
    }

    fn write_tar_gz(path: &Path, dir_name: &str, files: &[(&str, &[u8])]) {
        let file = fs::File::create(path).unwrap();
        let encoder = flate2::write::GzEncoder::new(file, flate2::Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        for (name, content) in files {
            let mut header = tar::Header::new_gnu();
            header.set_size(content.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            builder
                .append_data(&mut header, format!("{dir_name}/{name}"), *content)
                .unwrap();
        }
        builder.into_inner().unwrap().finish().unwrap();
    }

    #[test]
    fn archive_and_onnx_targets_use_per_model_dirs() {
        let dir = scratch_dir("variant-paths");
        let downloader = ModelDownloader::new(&dir);

        let archive = tar_gz_target("parakeet-v3-int8");
        assert_eq!(downloader.model_dir(&archive), dir.join("parakeet-v3-int8"));
        assert_eq!(downloader.file_path(&archive, "mmproj.gguf"), None);

        let onnx = file_target("silero-vad-v4");
        assert_eq!(
            downloader.file_path(&onnx, "model.onnx").unwrap(),
            dir.join("silero-vad-v4/model.onnx")
        );
        assert_eq!(
            downloader.file_path(&onnx, "model.onnx"),
            Some(dir.join("silero-vad-v4/model.onnx"))
        );
        assert_eq!(downloader.file_path(&onnx, "missing.onnx"), None);
        assert_eq!(downloader.file_path(&onnx, "mmproj.gguf"), None);

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn archive_download_extracts_into_model_dir() {
        let dir = scratch_dir("variant-extract");
        let downloader = ModelDownloader::new(&dir);
        let target = tar_gz_target("parakeet-v3-int8");
        assert!(!downloader.is_downloaded(&target));

        fs::create_dir_all(dir.join(".staging")).unwrap();
        write_tar_gz(
            &dir.join(".staging/parakeet-v3-int8.tar.gz"),
            "parakeet-tdt-0.6b-v3-int8",
            &[("encoder.onnx", b"enc"), ("tokens.txt", b"tok")],
        );
        let mut statuses = Vec::new();
        downloader
            .extract_if_archive(&target, &mut |progress| statuses.push(progress.status))
            .expect("extract");

        assert!(downloader.is_downloaded(&target));
        assert_eq!(
            fs::read(dir.join("parakeet-v3-int8/encoder.onnx")).unwrap(),
            b"enc"
        );
        assert_eq!(statuses, ["Extracting..."]);
        assert!(!dir.join(".staging/parakeet-v3-int8.tar.gz").exists());

        assert!(downloader.remove_downloaded(&target));
        assert!(!downloader.is_downloaded(&target));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn failed_archive_extraction_cleans_staging() {
        let dir = scratch_dir("variant-extract-failure");
        let downloader = ModelDownloader::new(&dir);
        let target = tar_gz_target("parakeet-v3-int8");
        let staging_dir = dir.join(".staging");
        fs::create_dir_all(&staging_dir).unwrap();
        fs::write(staging_dir.join("parakeet-v3-int8.tar.gz"), b"invalid").unwrap();

        assert!(downloader.extract_if_archive(&target, &mut |_| {}).is_err());
        assert!(!staging_dir.join("parakeet-v3-int8").exists());
        assert!(staging_dir.join("parakeet-v3-int8.tar.gz").exists());

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn onnx_target_downloaded_and_removed_via_model_file() {
        let dir = scratch_dir("variant-onnx");
        let downloader = ModelDownloader::new(&dir);
        let target = file_target("silero-vad-v4");
        assert!(!downloader.is_downloaded(&target));

        write_gguf(
            &downloader.file_path(&target, "model.onnx").unwrap(),
            b"onnxbytes",
        );
        assert!(downloader.is_downloaded(&target));

        assert!(downloader.remove_downloaded(&target));
        assert!(!downloader.is_downloaded(&target));
        assert!(!dir.join("silero-vad-v4").exists());

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn display_progress_composes_percent_and_status() {
        let progress = Progress {
            label: "Model".to_string(),
            downloaded_bytes: 512 * 1024 * 1024,
            total_bytes: Some(2 * 1024 * 1024 * 1024),
            file_downloaded_bytes: 512 * 1024 * 1024,
            file_total_bytes: Some(2 * 1024 * 1024 * 1024),
            percentage: 25.0,
            elapsed_ms: 0,
            bytes_per_second: 0.0,
            file_elapsed_ms: 0,
            file_bytes_per_second: 0.0,
            retry_count: 0,
            file_retry_count: 0,
            file_complete: false,
            complete: false,
        };

        let display = display_progress(progress);
        assert_eq!(display.percent, 25);
        assert_eq!(display.status, "Downloading... 512.0 MB / 2.0 GB");
        assert_eq!(display.log_line, None);

        let unknown_total = Progress {
            total_bytes: None,
            ..display_to_progress_stub()
        };
        let display = display_progress(unknown_total);
        assert_eq!(display.percent, 0);
        assert_eq!(display.status, "Downloading model... 100.0 B");

        let file_complete = Progress {
            file_complete: true,
            file_bytes_per_second: 2048.0,
            ..display_to_progress_stub()
        };
        let display = display_progress(file_complete);
        assert_eq!(
            display.log_line.as_deref(),
            Some(
                "Model download file complete label=Model bytes=100 elapsedMs=0 rate=2.0 KB/s retries=0"
            )
        );
    }

    fn display_to_progress_stub() -> Progress {
        Progress {
            label: "Model".to_string(),
            downloaded_bytes: 100,
            total_bytes: None,
            file_downloaded_bytes: 100,
            file_total_bytes: None,
            percentage: 0.0,
            elapsed_ms: 0,
            bytes_per_second: 0.0,
            file_elapsed_ms: 0,
            file_bytes_per_second: 0.0,
            retry_count: 0,
            file_retry_count: 0,
            file_complete: false,
            complete: false,
        }
    }
}
