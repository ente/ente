use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, PoisonError};
use std::time::Duration;

use tokio::runtime::Builder;

use crate::archive;
use crate::download::{self, Progress, Target};
use crate::gguf;

#[derive(Debug, Clone)]
pub enum ModelDownloadTarget {
    Gguf {
        id: String,
        url: String,
        mmproj_url: Option<String>,
    },
    TarGz {
        id: String,
        url: String,
    },
    Onnx {
        id: String,
        url: String,
    },
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
    models_dir: PathBuf,
    cancelled: AtomicBool,
    active: AtomicBool,
    download_lock: Mutex<()>,
}

impl ModelDownloader {
    pub fn new(models_dir: impl Into<PathBuf>) -> Self {
        let models_dir = models_dir.into();
        let _ = fs::create_dir_all(&models_dir);
        Self {
            models_dir,
            cancelled: AtomicBool::new(false),
            active: AtomicBool::new(false),
            download_lock: Mutex::new(()),
        }
    }

    pub fn model_path(&self, target: &ModelDownloadTarget) -> PathBuf {
        model_path(&self.models_dir, target)
    }

    pub fn mmproj_path(&self, target: &ModelDownloadTarget) -> Option<PathBuf> {
        match target {
            ModelDownloadTarget::Gguf {
                id,
                url,
                mmproj_url,
            } => gguf::mmproj_path(&self.models_dir, id, url, mmproj_url.as_deref()),
            ModelDownloadTarget::TarGz { .. } | ModelDownloadTarget::Onnx { .. } => None,
        }
    }

    pub fn is_downloaded(&self, target: &ModelDownloadTarget) -> bool {
        match target {
            ModelDownloadTarget::Gguf { .. } => self.fetch_targets(target).iter().all(|entry| {
                let path = Path::new(&entry.destination_path);
                path.exists() && gguf::looks_like_gguf(path)
            }),
            ModelDownloadTarget::TarGz { .. } => self.model_path(target).is_dir(),
            ModelDownloadTarget::Onnx { .. } => is_non_empty_file(&self.model_path(target)),
        }
    }

    pub fn is_download_active(&self) -> bool {
        self.active.load(Ordering::SeqCst)
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn remove_downloaded(&self, target: &ModelDownloadTarget) -> bool {
        if let ModelDownloadTarget::TarGz { .. } = target {
            let dir = self.model_path(target);
            return dir.exists() && fs::remove_dir_all(dir).is_ok();
        }
        let mut removed = false;
        for entry in self.fetch_targets(target) {
            let path = Path::new(&entry.destination_path);
            if path.exists() {
                let _ = fs::remove_file(path);
                removed = true;
            }
            if let Some(parent) = path.parent() {
                let _ = fs::remove_dir(parent);
            }
        }
        removed
    }

    /// Returns whether a network download ran; false when everything was
    /// already present.
    pub fn download(
        &self,
        targets: &[ModelDownloadTarget],
        mut on_progress: impl FnMut(ModelDownloadProgress),
        is_cancelled: impl Fn() -> bool,
    ) -> Result<bool, download::Error> {
        let _guard = self
            .download_lock
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let pending = targets
            .iter()
            .filter(|target| !self.is_downloaded(target))
            .collect::<Vec<_>>();
        if pending.is_empty() {
            return Ok(false);
        }

        self.cancelled.store(false, Ordering::SeqCst);
        self.active.store(true, Ordering::SeqCst);
        let result = download::fetch(
            pending
                .iter()
                .flat_map(|target| self.fetch_targets(target))
                .collect(),
            validate_target,
            |progress| on_progress(display_progress(progress)),
            || self.cancelled.load(Ordering::SeqCst) || is_cancelled(),
        )
        .and_then(|()| {
            for target in &pending {
                self.extract_if_archive(target, &mut on_progress)?;
            }
            Ok(())
        });
        self.active.store(false, Ordering::SeqCst);
        result.map(|()| true)
    }

    fn extract_if_archive(
        &self,
        target: &ModelDownloadTarget,
        on_progress: &mut impl FnMut(ModelDownloadProgress),
    ) -> Result<(), download::Error> {
        let ModelDownloadTarget::TarGz { id, .. } = target else {
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
        let result = archive::extract_tar_gz(
            &archive_path,
            &self.staging_dir().join(id),
            &self.model_path(target),
        );
        let _ = fs::remove_file(download::metadata_path_for(&archive_path));
        let _ = fs::remove_file(&archive_path);
        result
    }

    fn staging_dir(&self) -> PathBuf {
        self.models_dir.join(".staging")
    }

    pub fn estimated_download_size(&self, target: &ModelDownloadTarget) -> Option<i64> {
        let runtime = Builder::new_current_thread()
            .enable_io()
            .enable_time()
            .build()
            .ok()?;
        runtime.block_on(async {
            let client = reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(30))
                .build()
                .ok()?;
            let mut total: i64 = 0;
            let mut any = false;
            for entry in self.fetch_targets(target) {
                let path = Path::new(&entry.destination_path);
                let size = if path.exists() {
                    fs::metadata(path).ok().map(|m| m.len()).filter(|s| *s > 0)
                } else {
                    download::probe_content_length(&client, &entry.url).await
                };
                if let Some(size) = size {
                    any = true;
                    total = total.saturating_add(size as i64);
                }
            }
            any.then_some(total)
        })
    }

    fn fetch_targets(&self, target: &ModelDownloadTarget) -> Vec<Target> {
        match target {
            ModelDownloadTarget::Gguf {
                id,
                url,
                mmproj_url,
            } => gguf::expected_targets(&self.models_dir, id, url, mmproj_url.as_deref()),
            ModelDownloadTarget::TarGz { id, url } => vec![Target {
                label: "Model".to_string(),
                url: url.clone(),
                destination_path: self
                    .staging_dir()
                    .join(format!("{id}.tar.gz"))
                    .display()
                    .to_string(),
            }],
            ModelDownloadTarget::Onnx { url, .. } => vec![Target {
                label: "Model".to_string(),
                url: url.clone(),
                destination_path: self.model_path(target).display().to_string(),
            }],
        }
    }
}

fn model_path(models_dir: &Path, target: &ModelDownloadTarget) -> PathBuf {
    match target {
        ModelDownloadTarget::Gguf {
            id,
            url,
            mmproj_url,
        } => gguf::model_path(models_dir, id, url, mmproj_url.as_deref()),
        ModelDownloadTarget::TarGz { id, .. } => models_dir.join(id),
        ModelDownloadTarget::Onnx { id, .. } => models_dir.join(id).join("model.onnx"),
    }
}

fn validate_target(target: &Target, path: &Path) -> Result<(), download::Error> {
    if target.destination_path.ends_with(".tar.gz") {
        if !archive::looks_like_gzip(path) {
            return Err(download::Error::Validation(format!(
                "{} is not a gzip archive",
                path.display()
            )));
        }
        return Ok(());
    }
    if target.destination_path.ends_with(".onnx") {
        if !is_non_empty_file(path) {
            return Err(download::Error::Validation(format!(
                "{} is empty",
                path.display()
            )));
        }
        return Ok(());
    }
    gguf::validate_gguf(path)
}

fn is_non_empty_file(path: &Path) -> bool {
    path.metadata()
        .map(|metadata| metadata.is_file() && metadata.len() > 0)
        .unwrap_or(false)
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

pub fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KB", "MB", "GB"];
    let mut size = bytes as f64;
    let mut unit = 0;
    while size >= 1024.0 && unit < UNITS.len() - 1 {
        size /= 1024.0;
        unit += 1;
    }
    format!("{size:.1} {}", UNITS[unit])
}

fn migrate_legacy_dir(models_dir: &Path, legacy_dir: &Path, targets: &[ModelDownloadTarget]) {
    if !legacy_dir.exists() {
        return;
    }
    let legacy_models = legacy_dir.join("models");
    let hashed_dirs = [legacy_models.join("custom")];
    if adopt_targets(models_dir, targets, &hashed_dirs, &legacy_models) {
        let _ = fs::remove_dir_all(legacy_dir);
    }
}

pub fn migrate_flat_models_dir(models_dir: &Path, targets: &[ModelDownloadTarget]) {
    if !models_dir.exists() {
        return;
    }
    let hashed_dirs = [models_dir.join("custom"), models_dir.to_path_buf()];
    if !adopt_targets(models_dir, targets, &hashed_dirs, models_dir) {
        return;
    }
    let Ok(entries) = fs::read_dir(models_dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            let _ = fs::remove_file(&path);
        } else if path.file_name().is_some_and(|name| name == "custom") {
            let _ = fs::remove_dir_all(&path);
        }
    }
}

pub fn migrate_ensu_legacy_models(
    models_dir: &Path,
    llm_legacy_dir: Option<&Path>,
    transcription_legacy_dir: &Path,
    llm_targets: &[ModelDownloadTarget],
    transcription_model: &ModelDownloadTarget,
    voice_activity_model: &ModelDownloadTarget,
) {
    if let Some(llm_legacy_dir) = llm_legacy_dir {
        migrate_legacy_dir(models_dir, llm_legacy_dir, llm_targets);
    }
    migrate_legacy_transcription_dir(
        models_dir,
        transcription_legacy_dir,
        transcription_model,
        voice_activity_model,
    );
}

fn migrate_legacy_transcription_dir(
    models_dir: &Path,
    legacy_dir: &Path,
    model: &ModelDownloadTarget,
    vad: &ModelDownloadTarget,
) {
    const LEGACY_MODEL_DIR_NAME: &str = "parakeet-tdt-0.6b-v3-int8";
    const LEGACY_MODEL_ID: &str = "parakeet-v3-int8";
    const LEGACY_VAD_FILE_NAME: &str = "silero_vad_v4.onnx";
    const LEGACY_VAD_ID: &str = "silero-vad-v4";
    if !legacy_dir.exists() {
        return;
    }
    let mut all_moved = true;

    if matches!(model, ModelDownloadTarget::TarGz { id, .. } if id == LEGACY_MODEL_ID) {
        let dest = model_path(models_dir, model);
        if !dest.exists() {
            let source = legacy_dir.join(LEGACY_MODEL_DIR_NAME);
            if source.is_dir() {
                let _ = fs::create_dir_all(models_dir);
                if fs::rename(&source, &dest).is_err() {
                    all_moved = false;
                }
            }
        }
    }

    if matches!(vad, ModelDownloadTarget::Onnx { id, .. } if id == LEGACY_VAD_ID) {
        let dest = model_path(models_dir, vad);
        if !dest.exists() {
            let source = legacy_dir.join(LEGACY_VAD_FILE_NAME);
            if is_non_empty_file(&source) && !move_file(&source, &dest) {
                all_moved = false;
            }
        }
    }

    if all_moved {
        let _ = fs::remove_dir_all(legacy_dir);
    }
}

fn sidecar_url(path: &Path) -> Option<String> {
    let sidecar = PathBuf::from(format!("{}.metadata.json", path.display()));
    let text = fs::read_to_string(sidecar).ok()?;
    let value: serde_json::Value = serde_json::from_str(&text).ok()?;
    value["url"].as_str().map(String::from)
}

fn adopt_targets(
    models_dir: &Path,
    targets: &[ModelDownloadTarget],
    hashed_dirs: &[PathBuf],
    flat_dir: &Path,
) -> bool {
    let mut plans: Vec<Vec<(String, &str, PathBuf)>> = Vec::new();
    for target in targets {
        let ModelDownloadTarget::Gguf {
            id,
            url,
            mmproj_url,
        } = target
        else {
            continue;
        };
        let mmproj_url = mmproj_url.as_deref();
        let mut plan = vec![(
            url.clone(),
            "model.gguf",
            gguf::model_path(models_dir, id, url, mmproj_url),
        )];
        if let Some(dest) = gguf::mmproj_path(models_dir, id, url, mmproj_url) {
            plan.push((
                gguf::trimmed(mmproj_url).unwrap().to_string(),
                "mmproj.gguf",
                dest,
            ));
        }
        plans.push(plan);
    }

    let mut basename_urls: HashMap<String, HashSet<&str>> = HashMap::new();
    for plan in &plans {
        for (url, fallback, _) in plan {
            basename_urls
                .entry(gguf::filename_for_url(url, fallback))
                .or_default()
                .insert(url.as_str());
        }
    }

    let mut all_moved = true;
    for plan in &plans {
        let sources: Vec<Option<Option<PathBuf>>> = plan
            .iter()
            .map(|(url, fallback, dest)| {
                if dest.exists() {
                    return Some(None);
                }
                let basename = gguf::filename_for_url(url, fallback);
                for dir in hashed_dirs {
                    let hashed = dir.join(format!("{}_{basename}", gguf::sha256_hex(url)));
                    if gguf::looks_like_gguf(&hashed) {
                        return Some(Some(hashed));
                    }
                }
                let flat = flat_dir.join(&basename);
                if gguf::looks_like_gguf(&flat) {
                    match sidecar_url(&flat) {
                        Some(sidecar) => {
                            if sidecar == *url {
                                return Some(Some(flat));
                            }
                        }
                        None => {
                            if basename_urls[&basename].len() == 1 {
                                return Some(Some(flat));
                            }
                        }
                    }
                }
                None
            })
            .collect();
        if sources.iter().any(Option::is_none) {
            continue;
        }
        for ((_, _, dest), source) in plan.iter().zip(sources) {
            let Some(Some(source)) = source else {
                continue;
            };
            if !move_file(&source, dest) {
                all_moved = false;
            }
        }
    }
    all_moved
}

fn move_file(source: &Path, dest: &Path) -> bool {
    if let Some(parent) = dest.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if fs::rename(source, dest).is_ok() {
        return true;
    }
    let staged = PathBuf::from(format!("{}.migrating", dest.display()));
    if fs::copy(source, &staged)
        .and_then(|_| fs::rename(&staged, dest))
        .is_err()
    {
        let _ = fs::remove_file(&staged);
        return false;
    }
    true
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

    fn target(id: &str) -> ModelDownloadTarget {
        ModelDownloadTarget::Gguf {
            id: id.to_string(),
            url: "https://example.org/models/main.gguf?download=true".to_string(),
            mmproj_url: Some("https://example.org/models/mmproj.gguf".to_string()),
        }
    }

    fn write_gguf(path: &Path, content: &[u8]) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    #[test]
    fn paths_are_keyed_by_preset_id_or_custom_pair_hash() {
        let dir = scratch_dir("paths");
        let downloader = ModelDownloader::new(&dir);

        assert_eq!(
            downloader.model_path(&target("qwen-2b-q8")),
            dir.join("qwen-2b-q8/model.gguf")
        );
        assert_eq!(
            downloader.mmproj_path(&target("qwen-2b-q8")),
            Some(dir.join("qwen-2b-q8/mmproj.gguf"))
        );

        let custom = downloader.model_path(&target("custom:1"));
        let key = custom
            .parent()
            .unwrap()
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        assert!(key.starts_with("custom-"));
        assert_eq!(key.len(), "custom-".len() + 16);
        assert_eq!(custom.file_name().unwrap(), "model.gguf");
        assert_eq!(
            downloader.mmproj_path(&target("custom:1")),
            Some(custom.with_file_name("mmproj.gguf"))
        );

        let other_mmproj = ModelDownloadTarget::Gguf {
            id: "custom:1".to_string(),
            url: "https://example.org/models/main.gguf?download=true".to_string(),
            mmproj_url: Some("https://example.org/models/other.gguf".to_string()),
        };
        assert_ne!(downloader.model_path(&other_mmproj), custom);

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn is_downloaded_requires_gguf_magic_on_all_files() {
        let dir = scratch_dir("is-downloaded");
        let downloader = ModelDownloader::new(&dir);
        let target = target("qwen-2b-q8");
        let model = downloader.model_path(&target);
        let mmproj = downloader.mmproj_path(&target).unwrap();

        assert!(!downloader.is_downloaded(&target));

        write_gguf(&model, b"GGUFdata");
        assert!(!downloader.is_downloaded(&target));

        write_gguf(&mmproj, b"not-a-model");
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
        write_gguf(&downloader.model_path(&target), b"GGUFdata");
        write_gguf(&downloader.mmproj_path(&target).unwrap(), b"GGUFdata");

        let downloaded = downloader
            .download(std::slice::from_ref(&target), |_| {}, || false)
            .expect("skip without network");
        assert!(!downloaded);

        let _ = fs::remove_dir_all(dir);
    }

    fn tar_gz_target(id: &str) -> ModelDownloadTarget {
        ModelDownloadTarget::TarGz {
            id: id.to_string(),
            url: format!("https://models.example.org/{id}.tar.gz"),
        }
    }

    fn onnx_target(id: &str) -> ModelDownloadTarget {
        ModelDownloadTarget::Onnx {
            id: id.to_string(),
            url: format!("https://models.example.org/{id}.onnx"),
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
        assert_eq!(
            downloader.model_path(&archive),
            dir.join("parakeet-v3-int8")
        );
        assert_eq!(downloader.mmproj_path(&archive), None);

        let onnx = onnx_target("silero-vad-v4");
        assert_eq!(
            downloader.model_path(&onnx),
            dir.join("silero-vad-v4/model.onnx")
        );
        assert_eq!(downloader.mmproj_path(&onnx), None);

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
    fn onnx_target_downloaded_and_removed_via_model_file() {
        let dir = scratch_dir("variant-onnx");
        let downloader = ModelDownloader::new(&dir);
        let target = onnx_target("silero-vad-v4");
        assert!(!downloader.is_downloaded(&target));

        write_gguf(&downloader.model_path(&target), b"onnxbytes");
        assert!(downloader.is_downloaded(&target));

        assert!(downloader.remove_downloaded(&target));
        assert!(!downloader.is_downloaded(&target));
        assert!(!dir.join("silero-vad-v4").exists());

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn migrate_transcription_moves_model_dir_and_vad_file() {
        let base = scratch_dir("migrate-transcription");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"enc",
        )
        .unwrap();
        fs::write(legacy.join("silero_vad_v4.onnx"), b"vad").unwrap();
        fs::write(legacy.join("stale.partial"), b"junk").unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v3-int8");
        let vad = ModelDownloadTarget::Onnx {
            id: "silero-vad-v4".to_string(),
            url: "https://models.example.org/silero_vad_v4.onnx".to_string(),
        };
        migrate_legacy_transcription_dir(&models_dir, &legacy, &model, &vad);

        let downloader = ModelDownloader::new(&models_dir);
        assert!(downloader.is_downloaded(&model));
        assert!(downloader.is_downloaded(&vad));
        assert_eq!(
            fs::read(models_dir.join("parakeet-v3-int8/encoder.onnx")).unwrap(),
            b"enc"
        );
        assert_eq!(
            fs::read(models_dir.join("silero-vad-v4/model.onnx")).unwrap(),
            b"vad"
        );
        assert!(!legacy.exists());

        migrate_legacy_transcription_dir(&models_dir, &legacy, &model, &vad);
        assert!(downloader.is_downloaded(&model));

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_transcription_keeps_existing_destinations() {
        let base = scratch_dir("migrate-transcription-existing");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"old",
        )
        .unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v3-int8");
        let vad = onnx_target("silero-vad-v4");
        fs::create_dir_all(models_dir.join("parakeet-v3-int8")).unwrap();
        fs::write(models_dir.join("parakeet-v3-int8/encoder.onnx"), b"new").unwrap();

        migrate_legacy_transcription_dir(&models_dir, &legacy, &model, &vad);

        assert_eq!(
            fs::read(models_dir.join("parakeet-v3-int8/encoder.onnx")).unwrap(),
            b"new"
        );
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_transcription_adopts_nothing_when_target_ids_differ() {
        let base = scratch_dir("migrate-transcription-mismatch");
        let legacy = base.join("transcription");
        fs::create_dir_all(legacy.join("parakeet-tdt-0.6b-v3-int8")).unwrap();
        fs::write(
            legacy.join("parakeet-tdt-0.6b-v3-int8/encoder.onnx"),
            b"enc",
        )
        .unwrap();
        fs::write(legacy.join("silero_vad_v4.onnx"), b"vad").unwrap();

        let models_dir = base.join("models");
        let model = tar_gz_target("parakeet-v4-int8");
        let vad = onnx_target("silero-vad-v5");
        migrate_legacy_transcription_dir(&models_dir, &legacy, &model, &vad);

        let downloader = ModelDownloader::new(&models_dir);
        assert!(!downloader.is_downloaded(&model));
        assert!(!downloader.is_downloaded(&vad));
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_adopts_known_files_and_discards_legacy_dir() {
        let base = scratch_dir("migrate");
        let legacy = base.join("llm");
        let legacy_models = legacy.join("models");
        fs::create_dir_all(legacy_models.join("custom")).unwrap();

        fs::write(legacy_models.join("main.gguf"), b"GGUFmain").unwrap();
        fs::write(legacy_models.join("mmproj.gguf"), b"GGUFmmproj").unwrap();

        let custom_url = "https://example.org/custom/other-main.gguf";
        let custom = ModelDownloadTarget::Gguf {
            id: "custom:1".to_string(),
            url: custom_url.to_string(),
            mmproj_url: None,
        };
        fs::write(
            legacy_models
                .join("custom")
                .join(format!("{}_other-main.gguf", gguf::sha256_hex(custom_url))),
            b"GGUFcustom",
        )
        .unwrap();

        fs::write(legacy_models.join("main.gguf.tmp"), b"GGUFpartial").unwrap();
        fs::write(legacy_models.join("main.gguf.metadata.json"), b"{}").unwrap();
        fs::write(legacy_models.join("orphan.gguf"), b"GGUForphan").unwrap();

        let models_dir = base.join("models");
        let preset = target("qwen-2b-q8");
        migrate_legacy_dir(&models_dir, &legacy, &[preset.clone(), custom.clone()]);

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(downloader.model_path(&preset)).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(downloader.mmproj_path(&preset).unwrap()).unwrap(),
            b"GGUFmmproj"
        );
        assert_eq!(
            fs::read(downloader.model_path(&custom)).unwrap(),
            b"GGUFcustom"
        );
        assert_eq!(fs::read_dir(&models_dir).unwrap().count(), 2);
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_adopts_targets_only_when_every_file_resolves() {
        let base = scratch_dir("migrate-ambiguous");
        let legacy = base.join("llm");
        let legacy_models = legacy.join("models");
        fs::create_dir_all(&legacy_models).unwrap();
        fs::write(legacy_models.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(legacy_models.join("b.gguf"), b"GGUFb").unwrap();
        fs::write(legacy_models.join("mmproj-F16.gguf"), b"GGUFshared").unwrap();

        let targets = ["a", "b"].map(|name| ModelDownloadTarget::Gguf {
            id: format!("preset-{name}"),
            url: format!("https://example.org/{name}/{name}.gguf"),
            mmproj_url: Some(format!("https://example.org/{name}/mmproj-F16.gguf")),
        });

        let models_dir = base.join("models");
        migrate_legacy_dir(&models_dir, &legacy, &targets);

        assert!(!models_dir.exists() || fs::read_dir(&models_dir).unwrap().count() == 0);
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
    }

    #[test]
    fn migrate_flat_models_dir_adopts_known_files_and_cleans_root() {
        let models_dir = scratch_dir("flat-migrate");
        fs::create_dir_all(models_dir.join("custom")).unwrap();

        let preset = target("qwen-2b-q8");
        fs::write(models_dir.join("main.gguf"), b"GGUFmain").unwrap();
        let mmproj_hashed = format!(
            "{}_mmproj.gguf",
            gguf::sha256_hex("https://example.org/models/mmproj.gguf")
        );
        fs::write(models_dir.join(mmproj_hashed), b"GGUFmm").unwrap();

        let custom_url = "https://example.org/custom/other-main.gguf";
        let custom = ModelDownloadTarget::Gguf {
            id: "custom:1".to_string(),
            url: custom_url.to_string(),
            mmproj_url: None,
        };
        fs::write(
            models_dir
                .join("custom")
                .join(format!("{}_other-main.gguf", gguf::sha256_hex(custom_url))),
            b"GGUFcustom",
        )
        .unwrap();

        fs::write(models_dir.join("orphan.gguf"), b"GGUForphan").unwrap();
        fs::write(models_dir.join("main.gguf.tmp"), b"GGUFpartial").unwrap();
        let downloader = ModelDownloader::new(&models_dir);
        write_gguf(
            &models_dir.join("other-key").join("model.gguf"),
            b"GGUFkeep",
        );

        migrate_flat_models_dir(&models_dir, &[preset.clone(), custom.clone()]);

        assert_eq!(
            fs::read(downloader.model_path(&preset)).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(downloader.mmproj_path(&preset).unwrap()).unwrap(),
            b"GGUFmm"
        );
        assert_eq!(
            fs::read(downloader.model_path(&custom)).unwrap(),
            b"GGUFcustom"
        );
        assert_eq!(
            fs::read(models_dir.join("other-key/model.gguf")).unwrap(),
            b"GGUFkeep"
        );
        assert!(!models_dir.join("custom").exists());
        let root_files = fs::read_dir(&models_dir)
            .unwrap()
            .flatten()
            .filter(|entry| entry.path().is_file())
            .count();
        assert_eq!(root_files, 0);

        migrate_flat_models_dir(&models_dir, &[preset.clone(), custom]);
        assert_eq!(
            fs::read(downloader.model_path(&preset)).unwrap(),
            b"GGUFmain"
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_adopts_sidecarless_files_for_duplicated_targets() {
        let models_dir = scratch_dir("flat-duplicate-targets");
        fs::create_dir_all(&models_dir).unwrap();
        fs::write(models_dir.join("main.gguf"), b"GGUFmain").unwrap();
        fs::write(models_dir.join("mmproj.gguf"), b"GGUFmm").unwrap();

        let preset = target("lfm-vl-1.6b");
        migrate_flat_models_dir(&models_dir, &[preset.clone(), preset.clone()]);

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(downloader.model_path(&preset)).unwrap(),
            b"GGUFmain"
        );
        assert_eq!(
            fs::read(downloader.mmproj_path(&preset).unwrap()).unwrap(),
            b"GGUFmm"
        );

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_resolves_ambiguity_via_metadata_sidecars() {
        let models_dir = scratch_dir("flat-sidecar");
        fs::create_dir_all(&models_dir).unwrap();

        let targets = ["a", "b"].map(|name| ModelDownloadTarget::Gguf {
            id: format!("preset-{name}"),
            url: format!("https://example.org/{name}/{name}.gguf"),
            mmproj_url: Some(format!("https://example.org/{name}/mmproj-F16.gguf")),
        });

        fs::write(models_dir.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(
            models_dir.join("a.gguf.metadata.json"),
            br#"{"url": "https://example.org/a/a.gguf"}"#,
        )
        .unwrap();
        fs::write(models_dir.join("mmproj-F16.gguf"), b"GGUFmma").unwrap();
        fs::write(
            models_dir.join("mmproj-F16.gguf.metadata.json"),
            br#"{"url": "https://example.org/a/mmproj-F16.gguf"}"#,
        )
        .unwrap();

        migrate_flat_models_dir(&models_dir, &targets);

        let downloader = ModelDownloader::new(&models_dir);
        assert_eq!(
            fs::read(downloader.model_path(&targets[0])).unwrap(),
            b"GGUFa"
        );
        assert_eq!(
            fs::read(downloader.mmproj_path(&targets[0]).unwrap()).unwrap(),
            b"GGUFmma"
        );
        assert!(!downloader.model_path(&targets[1]).exists());

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_rejects_files_whose_sidecar_disagrees() {
        let models_dir = scratch_dir("flat-sidecar-mismatch");
        fs::create_dir_all(&models_dir).unwrap();

        let preset = target("qwen-2b-q8");
        fs::write(models_dir.join("main.gguf"), b"GGUFstale").unwrap();
        fs::write(
            models_dir.join("main.gguf.metadata.json"),
            br#"{"url": "https://example.org/elsewhere/main.gguf"}"#,
        )
        .unwrap();

        migrate_flat_models_dir(&models_dir, std::slice::from_ref(&preset));

        let downloader = ModelDownloader::new(&models_dir);
        assert!(!downloader.model_path(&preset).exists());

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_flat_models_dir_drops_targets_with_ambiguous_basenames() {
        let models_dir = scratch_dir("flat-ambiguous");
        fs::create_dir_all(&models_dir).unwrap();
        fs::write(models_dir.join("a.gguf"), b"GGUFa").unwrap();
        fs::write(models_dir.join("mmproj-F16.gguf"), b"GGUFshared").unwrap();

        let targets = ["a", "b"].map(|name| ModelDownloadTarget::Gguf {
            id: format!("preset-{name}"),
            url: format!("https://example.org/{name}/{name}.gguf"),
            mmproj_url: Some(format!("https://example.org/{name}/mmproj-F16.gguf")),
        });

        migrate_flat_models_dir(&models_dir, &targets);

        assert_eq!(fs::read_dir(&models_dir).unwrap().count(), 0);

        let _ = fs::remove_dir_all(models_dir);
    }

    #[test]
    fn migrate_keeps_existing_destination_files() {
        let base = scratch_dir("migrate-existing");
        let legacy = base.join("llm");
        fs::create_dir_all(legacy.join("models")).unwrap();
        fs::write(legacy.join("models/main.gguf"), b"GGUFold").unwrap();
        fs::write(legacy.join("models/mmproj.gguf"), b"GGUFmm").unwrap();

        let models_dir = base.join("models");
        let preset = target("qwen-2b-q8");
        let downloader = ModelDownloader::new(&models_dir);
        write_gguf(&downloader.model_path(&preset), b"GGUFnew");

        migrate_legacy_dir(&models_dir, &legacy, std::slice::from_ref(&preset));

        assert_eq!(
            fs::read(downloader.model_path(&preset)).unwrap(),
            b"GGUFnew"
        );
        assert_eq!(
            fs::read(downloader.mmproj_path(&preset).unwrap()).unwrap(),
            b"GGUFmm"
        );
        assert!(!legacy.exists());

        let _ = fs::remove_dir_all(base);
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
