use std::cell::RefCell;
use std::fs::{self, File, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use futures_util::future::try_join_all;
use reqwest::header::{ACCEPT_RANGES, CONTENT_RANGE, ETAG, IF_RANGE, LAST_MODIFIED, RANGE};
use reqwest::{Client, Response, StatusCode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::runtime::Builder;
use tokio::time::timeout;

const MIN_RANGE_DOWNLOAD_BYTES: u64 = 1024 * 1024;
const MAX_ATTEMPTS: usize = 3;
const RANGE_DOWNLOAD_CONCURRENCY: usize = 4;
const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);
const RESPONSE_START_TIMEOUT: Duration = Duration::from_secs(30);
const READ_STALL_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Download cancelled")]
    Cancelled,
    #[error("Failed to download {label}: {source}")]
    Target {
        label: String,
        #[source]
        source: Box<Error>,
    },
    #[error("{single}; range download fallback was used after: {ranged}")]
    Fallback {
        single: Box<Error>,
        ranged: Box<Error>,
    },
    #[error("{0}")]
    Validation(String),
    #[error("HTTP {0}")]
    Http(u16),
    #[error("network: {0}")]
    Network(String),
    #[error("size mismatch: expected {expected} bytes, got {actual}")]
    SizeMismatch { expected: u64, actual: u64 },
    #[error("range protocol violation: {0}")]
    Protocol(String),
    #[error("invalid download target: {0}")]
    InvalidTarget(String),
    #[error("not enough storage space")]
    StorageFull,
    #[error(transparent)]
    Io(std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

impl From<std::io::Error> for Error {
    fn from(err: std::io::Error) -> Self {
        if err.kind() == std::io::ErrorKind::StorageFull {
            Error::StorageFull
        } else {
            Error::Io(err)
        }
    }
}

#[derive(Debug, Clone)]
pub struct Target {
    pub label: String,
    pub url: String,
    pub sha256: String,
    pub destination: PathBuf,
}

#[derive(Debug, Clone)]
pub struct Progress {
    pub label: String,
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub file_downloaded_bytes: u64,
    pub file_total_bytes: Option<u64>,
    pub percentage: f64,
    pub elapsed_ms: u64,
    pub bytes_per_second: f64,
    pub file_elapsed_ms: u64,
    pub file_bytes_per_second: f64,
    pub retry_count: u32,
    pub file_retry_count: u32,
    pub file_complete: bool,
    pub complete: bool,
}

#[derive(Clone, Default)]
pub struct CancellationToken {
    cancelled: Arc<AtomicBool>,
}

impl CancellationToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

#[derive(Debug, Clone, Copy)]
struct FileDownloadReport {
    final_size: u64,
    network_downloaded_bytes: u64,
    elapsed: Duration,
    retry_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PartialDownloadMetadata {
    url: String,
    etag: Option<String>,
    last_modified: Option<String>,
}

#[derive(Debug, Clone)]
struct ResponseMetadata {
    etag: Option<String>,
    last_modified: Option<String>,
}

#[derive(Debug, Clone, Default)]
struct DownloadProbe {
    content_length: Option<u64>,
    supports_ranges: bool,
    response_metadata: Option<ResponseMetadata>,
}

#[derive(Debug, Clone, Copy)]
struct FileProgress {
    downloaded_bytes: u64,
    total_bytes: Option<u64>,
    network_downloaded_bytes: u64,
    elapsed: Duration,
    retry_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RangeDownloadMetadata {
    url: String,
    size_bytes: u64,
    etag: Option<String>,
    last_modified: Option<String>,
    ranges: Vec<RangeDownloadPartMetadata>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
struct RangeDownloadPartMetadata {
    start: u64,
    end: u64,
    complete: bool,
}

#[derive(Debug, Clone, Copy)]
struct RangePartState {
    downloaded_bytes: u64,
    network_downloaded_bytes: u64,
    retry_count: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ContentRange {
    start: u64,
    end: u64,
    total: Option<u64>,
}

#[derive(Clone)]
pub struct Downloader {
    client: Client,
}

impl Downloader {
    pub fn new() -> Result<Self, Error> {
        Ok(Self {
            client: build_client()?,
        })
    }

    pub(crate) fn client(&self) -> &Client {
        &self.client
    }

    pub async fn download(
        &self,
        targets: Vec<Target>,
        on_progress: impl FnMut(Progress) + Send,
        cancellation: CancellationToken,
    ) -> Result<(), Error> {
        fetch_async(&self.client, targets, on_progress, move || {
            cancellation.is_cancelled()
        })
        .await
    }
}

fn build_client() -> Result<Client, Error> {
    Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .build()
        .map_err(|err| Error::Network(err.to_string()))
}

pub(crate) fn fetch(
    downloader: &Downloader,
    targets: Vec<Target>,
    on_progress: impl FnMut(Progress),
    is_cancelled: impl Fn() -> bool,
) -> Result<(), Error> {
    let runtime = Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()?;
    runtime.block_on(fetch_async(
        &downloader.client,
        targets,
        on_progress,
        is_cancelled,
    ))
}

async fn fetch_async(
    client: &Client,
    targets: Vec<Target>,
    on_progress: impl FnMut(Progress),
    is_cancelled: impl Fn() -> bool,
) -> Result<(), Error> {
    if targets.is_empty() {
        return Ok(());
    }

    for target in &targets {
        let sha256 = &target.sha256;
        if sha256.len() != 64 || !sha256.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(Error::InvalidTarget(format!(
                "'{sha256}' is not a SHA-256 digest"
            )));
        }
    }

    if is_cancelled() {
        return Err(Error::Cancelled);
    }

    let download_started_at = Instant::now();
    let mut download_probes = Vec::with_capacity(targets.len());
    let mut cached = Vec::with_capacity(targets.len());

    for target in &targets {
        let destination = &target.destination;
        let is_cached = prepare_cached_download(target, destination);
        cached.push(is_cached);
        if is_cached {
            download_probes.push(DownloadProbe {
                content_length: file_size(destination),
                supports_ranges: false,
                response_metadata: None,
            });
        } else {
            download_probes.push(fetch_download_probe(client, &target.url).await);
        }
    }

    let total_bytes = if download_probes
        .iter()
        .all(|probe| probe.content_length.is_some())
    {
        let total = download_probes
            .iter()
            .filter_map(|probe| probe.content_length)
            .sum::<u64>();
        (total > 0).then_some(total)
    } else {
        None
    };

    let file_states = targets
        .iter()
        .zip(&download_probes)
        .zip(&cached)
        .map(|((target, probe), cached)| {
            let existing = existing_download_bytes(target, &target.destination, probe, *cached);
            FileProgress {
                downloaded_bytes: probe
                    .content_length
                    .map_or(existing, |value| existing.min(value)),
                total_bytes: probe.content_length,
                network_downloaded_bytes: 0,
                elapsed: Duration::ZERO,
                retry_count: 0,
            }
        })
        .collect::<Vec<_>>();
    let file_states = Rc::new(RefCell::new(file_states));
    let on_progress = Rc::new(RefCell::new(on_progress));

    emit_progress(
        ProgressPhase::Preparing,
        Duration::ZERO,
        total_bytes,
        &file_states,
        &on_progress,
    );

    for (index, target) in targets.iter().enumerate() {
        if cached[index] {
            continue;
        }
        if is_cancelled() {
            return Err(Error::Cancelled);
        }
        let destination = target.destination.clone();
        let download_probe = download_probes
            .get(index)
            .cloned()
            .unwrap_or_else(DownloadProbe::default);
        let expected_file_total = download_probe.content_length;
        let target_label = target.label.clone();
        let file_report = download_file(
            client,
            target,
            &destination,
            &download_probe,
            |file_progress| {
                {
                    let mut states = file_states.borrow_mut();
                    if let Some(state) = states.get_mut(index) {
                        *state = file_progress;
                    }
                }
                emit_progress(
                    ProgressPhase::File {
                        label: &target_label,
                        index,
                        complete: false,
                    },
                    download_started_at.elapsed(),
                    total_bytes,
                    &file_states,
                    &on_progress,
                );
            },
            &is_cancelled,
        )
        .await
        .map_err(|err| match err {
            Error::Cancelled => Error::Cancelled,
            err => Error::Target {
                label: target.label.clone(),
                source: Box::new(err),
            },
        })?;

        {
            let mut states = file_states.borrow_mut();
            if let Some(state) = states.get_mut(index) {
                state.downloaded_bytes = file_report.final_size;
                state.total_bytes = expected_file_total.or(Some(file_report.final_size));
                state.network_downloaded_bytes = file_report.network_downloaded_bytes;
                state.elapsed = file_report.elapsed;
                state.retry_count = file_report.retry_count;
            }
        }

        emit_progress(
            ProgressPhase::File {
                label: &target_label,
                index,
                complete: true,
            },
            download_started_at.elapsed(),
            total_bytes,
            &file_states,
            &on_progress,
        );
    }
    emit_progress(
        ProgressPhase::Complete,
        download_started_at.elapsed(),
        total_bytes,
        &file_states,
        &on_progress,
    );

    Ok(())
}

async fn download_file(
    client: &Client,
    target: &Target,
    destination: &Path,
    download_probe: &DownloadProbe,
    mut on_progress: impl FnMut(FileProgress),
    is_cancelled: &impl Fn() -> bool,
) -> Result<FileDownloadReport, Error> {
    let parent = destination
        .parent()
        .ok_or_else(|| Error::InvalidTarget(destination.display().to_string()))?;
    fs::create_dir_all(parent)?;

    let mut range_error = None;
    if let Some(total) = download_probe.content_length {
        if should_use_range_download(total, download_probe) {
            match download_file_ranged(
                client,
                target,
                destination,
                total,
                download_probe.response_metadata.clone(),
                &mut on_progress,
                is_cancelled,
            )
            .await
            {
                Ok(report) => return Ok(report),
                Err(err @ (Error::Cancelled | Error::Validation(_) | Error::StorageFull)) => {
                    return Err(err);
                }
                Err(err) => {
                    range_error = Some(err);
                    cleanup_range_download(destination);
                }
            }
        } else if range_metadata_path_for(destination).exists() {
            cleanup_range_download(destination);
        }
    } else if range_metadata_path_for(destination).exists() {
        cleanup_range_download(destination);
    }

    let single_result = download_file_single(
        client,
        target,
        destination,
        download_probe.content_length,
        &mut on_progress,
        is_cancelled,
    )
    .await;

    match (single_result, range_error) {
        (Ok(report), _) => Ok(report),
        (Err(single_error), Some(range_error)) => Err(Error::Fallback {
            single: Box::new(single_error),
            ranged: Box::new(range_error),
        }),
        (Err(single_error), None) => Err(single_error),
    }
}

async fn download_file_single(
    client: &Client,
    target: &Target,
    destination: &Path,
    expected_file_total: Option<u64>,
    on_progress: &mut dyn FnMut(FileProgress),
    is_cancelled: &impl Fn() -> bool,
) -> Result<FileDownloadReport, Error> {
    let tmp_path = tmp_path_for(destination);
    let partial_metadata_path = partial_metadata_path_for(destination);
    let file_started_at = Instant::now();
    let mut network_downloaded_bytes = 0u64;
    let mut retry_count = 0u32;

    for attempt in 1..=MAX_ATTEMPTS {
        if is_cancelled() {
            return Err(Error::Cancelled);
        }

        let tmp_size = file_size(&tmp_path).unwrap_or(0);
        let resume_validator = if tmp_size > 0 {
            partial_download_validator(destination, &target.url)
        } else {
            None
        };
        let resume_from = if resume_validator.is_some() {
            tmp_size
        } else {
            0
        };

        let mut response = match request_file(
            client,
            &target.url,
            resume_from,
            resume_validator.as_deref(),
        )
        .await
        {
            Ok(response) => response,
            Err(err) => {
                if attempt == MAX_ATTEMPTS {
                    return Err(err);
                }
                retry_count = retry_count.saturating_add(1);
                continue;
            }
        };

        if resume_from > 0 && response.status() == StatusCode::RANGE_NOT_SATISFIABLE {
            let _ = fs::remove_file(&tmp_path);
            let _ = fs::remove_file(&partial_metadata_path);
            if attempt == MAX_ATTEMPTS {
                return Err(Error::Http(416));
            }
            retry_count = retry_count.saturating_add(1);
            continue;
        }

        if !response.status().is_success() {
            if attempt == MAX_ATTEMPTS {
                return Err(Error::Http(response.status().as_u16()));
            }
            retry_count = retry_count.saturating_add(1);
            continue;
        }

        let append = resume_from > 0 && response.status() == StatusCode::PARTIAL_CONTENT;
        if append && resumed_content_range_start(&response) != Some(resume_from) {
            let _ = fs::remove_file(&tmp_path);
            let _ = fs::remove_file(&partial_metadata_path);
            if attempt == MAX_ATTEMPTS {
                return Err(Error::Protocol(
                    "server resumed from the wrong offset".to_string(),
                ));
            }
            retry_count = retry_count.saturating_add(1);
            continue;
        }
        let resume_from = if append { resume_from } else { 0 };
        let response_metadata = response_metadata(&response);
        let file_total = content_total(&response, resume_from).or(expected_file_total);

        if !append {
            if if_range_header_value(Some(&response_metadata)).is_some() {
                let _ = write_partial_download_metadata(destination, target, &response_metadata);
            } else {
                let _ = fs::remove_file(&partial_metadata_path);
            }
        }

        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .append(append)
            .truncate(!append)
            .open(&tmp_path)?;

        let mut downloaded = resume_from;
        let mut last_progress = Instant::now();
        let mut retry_attempt = false;

        on_progress(FileProgress {
            downloaded_bytes: downloaded,
            total_bytes: file_total,
            network_downloaded_bytes,
            elapsed: file_started_at.elapsed(),
            retry_count,
        });

        loop {
            if is_cancelled() {
                file.flush().ok();
                return Err(Error::Cancelled);
            }

            let chunk = match timeout(READ_STALL_TIMEOUT, response.chunk()).await {
                Ok(Ok(chunk)) => chunk,
                Ok(Err(err)) => {
                    file.flush().ok();
                    if attempt == MAX_ATTEMPTS {
                        return Err(Error::Network(err.to_string()));
                    }
                    retry_count = retry_count.saturating_add(1);
                    retry_attempt = true;
                    break;
                }
                Err(_) => {
                    file.flush().ok();
                    if attempt == MAX_ATTEMPTS {
                        return Err(Error::Network(format!(
                            "stalled for {} seconds",
                            READ_STALL_TIMEOUT.as_secs()
                        )));
                    }
                    retry_count = retry_count.saturating_add(1);
                    retry_attempt = true;
                    break;
                }
            };
            let Some(chunk) = chunk else {
                break;
            };

            file.write_all(&chunk)?;
            downloaded = downloaded.saturating_add(chunk.len() as u64);
            network_downloaded_bytes = network_downloaded_bytes.saturating_add(chunk.len() as u64);

            if last_progress.elapsed() >= PROGRESS_INTERVAL {
                on_progress(FileProgress {
                    downloaded_bytes: downloaded,
                    total_bytes: file_total,
                    network_downloaded_bytes,
                    elapsed: file_started_at.elapsed(),
                    retry_count,
                });
                last_progress = Instant::now();
            }
        }

        if retry_attempt {
            drop(file);
            continue;
        }

        file.flush()?;
        drop(file);

        on_progress(FileProgress {
            downloaded_bytes: downloaded,
            total_bytes: file_total,
            network_downloaded_bytes,
            elapsed: file_started_at.elapsed(),
            retry_count,
        });

        if let Some(total) = file_total
            && downloaded != total
        {
            if downloaded > total {
                let _ = fs::remove_file(&tmp_path);
                let _ = fs::remove_file(&partial_metadata_path);
            }
            if attempt == MAX_ATTEMPTS {
                return Err(Error::SizeMismatch {
                    expected: total,
                    actual: downloaded,
                });
            }
            retry_count = retry_count.saturating_add(1);
            continue;
        }

        if let Err(err) = check_sha256(&tmp_path, &target.sha256, &target.label) {
            let _ = fs::remove_file(&tmp_path);
            let _ = fs::remove_file(&partial_metadata_path);
            return Err(err);
        }

        if destination.exists() {
            fs::remove_file(destination)?;
        }
        fs::rename(&tmp_path, destination)?;
        let _ = fs::remove_file(range_metadata_path_for(destination));
        let _ = fs::remove_file(&partial_metadata_path);

        let final_size = file_size(destination).unwrap_or(downloaded);
        if final_size != downloaded {
            let _ = fs::remove_file(destination);
            return Err(Error::SizeMismatch {
                expected: downloaded,
                actual: final_size,
            });
        }

        return Ok(FileDownloadReport {
            final_size,
            network_downloaded_bytes,
            elapsed: file_started_at.elapsed(),
            retry_count,
        });
    }

    unreachable!("the final attempt returns")
}

async fn download_file_ranged(
    client: &Client,
    target: &Target,
    destination: &Path,
    total: u64,
    response_metadata: Option<ResponseMetadata>,
    on_progress: &mut dyn FnMut(FileProgress),
    is_cancelled: &impl Fn() -> bool,
) -> Result<FileDownloadReport, Error> {
    let tmp_path = tmp_path_for(destination);
    let range_metadata_path = range_metadata_path_for(destination);
    let file_started_at = Instant::now();
    let range_metadata =
        prepare_range_download_metadata(target, destination, total, response_metadata.clone())?;

    let file = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(&tmp_path)?;
    file.set_len(total)?;
    let file = Rc::new(file);

    let range_states = range_metadata
        .ranges
        .iter()
        .map(|range| RangePartState {
            downloaded_bytes: if range.complete {
                range_download_len(*range)
            } else {
                0
            },
            network_downloaded_bytes: 0,
            retry_count: 0,
        })
        .collect::<Vec<_>>();
    let range_states = Rc::new(RefCell::new(range_states));
    let range_metadata = Rc::new(RefCell::new(range_metadata));
    let on_progress = Rc::new(RefCell::new(on_progress));

    emit_range_file_progress(total, file_started_at, &range_states, &on_progress);

    let mut downloads = Vec::new();
    {
        let metadata = range_metadata.borrow();
        for (part_index, range) in metadata.ranges.iter().copied().enumerate() {
            if range.complete {
                continue;
            }

            let file = Rc::clone(&file);
            let range_states = Rc::clone(&range_states);
            let range_metadata = Rc::clone(&range_metadata);
            let range_metadata_path = range_metadata_path.clone();
            let response_metadata = response_metadata.clone();
            let on_progress = Rc::clone(&on_progress);

            downloads.push(async move {
                download_range_part(
                    client,
                    target,
                    file,
                    part_index,
                    range,
                    total,
                    response_metadata,
                    range_states,
                    range_metadata,
                    range_metadata_path,
                    file_started_at,
                    on_progress,
                    is_cancelled,
                )
                .await
            });
        }
    }

    try_join_all(downloads).await?;
    drop(file);

    emit_range_file_progress(total, file_started_at, &range_states, &on_progress);

    if let Err(err) = check_sha256(&tmp_path, &target.sha256, &target.label) {
        let _ = fs::remove_file(&tmp_path);
        let _ = fs::remove_file(&range_metadata_path);
        return Err(err);
    }

    if destination.exists() {
        fs::remove_file(destination)?;
    }
    fs::rename(&tmp_path, destination)?;
    let _ = fs::remove_file(&range_metadata_path);
    let _ = fs::remove_file(partial_metadata_path_for(destination));

    let final_size = file_size(destination).unwrap_or(total);
    if final_size != total {
        let _ = fs::remove_file(destination);
        return Err(Error::SizeMismatch {
            expected: total,
            actual: final_size,
        });
    }

    let network_downloaded_bytes = range_states
        .borrow()
        .iter()
        .map(|state| state.network_downloaded_bytes)
        .sum::<u64>();
    let retry_count = range_states
        .borrow()
        .iter()
        .map(|state| state.retry_count)
        .fold(0u32, u32::saturating_add);
    let elapsed = file_started_at.elapsed();
    Ok(FileDownloadReport {
        final_size,
        network_downloaded_bytes,
        elapsed,
        retry_count,
    })
}

#[allow(clippy::too_many_arguments)]
async fn download_range_part(
    client: &Client,
    target: &Target,
    file: Rc<File>,
    part_index: usize,
    range: RangeDownloadPartMetadata,
    total: u64,
    response_metadata: Option<ResponseMetadata>,
    range_states: Rc<RefCell<Vec<RangePartState>>>,
    range_metadata: Rc<RefCell<RangeDownloadMetadata>>,
    range_metadata_path: PathBuf,
    file_started_at: Instant,
    on_progress: Rc<RefCell<&mut dyn FnMut(FileProgress)>>,
    is_cancelled: &impl Fn() -> bool,
) -> Result<(), Error> {
    let range_len = range_download_len(range);

    for attempt in 1..=MAX_ATTEMPTS {
        if is_cancelled() {
            return Err(Error::Cancelled);
        }

        {
            let mut states = range_states.borrow_mut();
            if let Some(state) = states.get_mut(part_index) {
                state.downloaded_bytes = 0;
            }
        }
        emit_range_file_progress(total, file_started_at, &range_states, &on_progress);

        let mut response =
            match request_model_range(client, &target.url, range, response_metadata.as_ref()).await
            {
                Ok(response) => response,
                Err(err) => {
                    if attempt == MAX_ATTEMPTS {
                        return Err(err);
                    }
                    increment_range_retry(&range_states, part_index);
                    emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
                    continue;
                }
            };

        if response.status() != StatusCode::PARTIAL_CONTENT {
            if response.status() == StatusCode::OK
                || response.status() == StatusCode::RANGE_NOT_SATISFIABLE
            {
                return Err(Error::Http(response.status().as_u16()));
            }
            if attempt == MAX_ATTEMPTS {
                return Err(Error::Http(response.status().as_u16()));
            }
            increment_range_retry(&range_states, part_index);
            emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
            continue;
        }

        validate_range_response(&response, range, total)?;

        let mut downloaded_in_range = 0u64;
        let mut last_progress = Instant::now();
        let mut retry_attempt = false;

        loop {
            if is_cancelled() {
                return Err(Error::Cancelled);
            }

            let chunk = match timeout(READ_STALL_TIMEOUT, response.chunk()).await {
                Ok(Ok(chunk)) => chunk,
                Ok(Err(err)) => {
                    if attempt == MAX_ATTEMPTS {
                        return Err(Error::Network(err.to_string()));
                    }
                    increment_range_retry(&range_states, part_index);
                    retry_attempt = true;
                    break;
                }
                Err(_) => {
                    if attempt == MAX_ATTEMPTS {
                        return Err(Error::Network(format!(
                            "stalled for {} seconds",
                            READ_STALL_TIMEOUT.as_secs()
                        )));
                    }
                    increment_range_retry(&range_states, part_index);
                    retry_attempt = true;
                    break;
                }
            };
            let Some(chunk) = chunk else {
                break;
            };

            let chunk_len = chunk.len() as u64;
            if downloaded_in_range.saturating_add(chunk_len) > range_len {
                return Err(Error::Protocol(
                    "received more bytes than requested".to_string(),
                ));
            }

            write_all_at(
                file.as_ref(),
                chunk.as_ref(),
                range.start + downloaded_in_range,
            )?;
            downloaded_in_range = downloaded_in_range.saturating_add(chunk_len);

            {
                let mut states = range_states.borrow_mut();
                if let Some(state) = states.get_mut(part_index) {
                    state.downloaded_bytes = downloaded_in_range;
                    state.network_downloaded_bytes =
                        state.network_downloaded_bytes.saturating_add(chunk_len);
                }
            }

            if last_progress.elapsed() >= PROGRESS_INTERVAL {
                emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
                last_progress = Instant::now();
            }
        }

        if retry_attempt {
            emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
            continue;
        }

        if downloaded_in_range != range_len {
            if attempt == MAX_ATTEMPTS {
                return Err(Error::SizeMismatch {
                    expected: range_len,
                    actual: downloaded_in_range,
                });
            }
            increment_range_retry(&range_states, part_index);
            emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
            continue;
        }

        {
            let mut states = range_states.borrow_mut();
            if let Some(state) = states.get_mut(part_index) {
                state.downloaded_bytes = range_len;
            }
        }
        mark_range_complete(&range_metadata, &range_metadata_path, part_index)?;
        emit_range_file_progress(total, file_started_at, &range_states, &on_progress);
        return Ok(());
    }

    unreachable!("the final attempt returns")
}

async fn request_file(
    client: &Client,
    url: &str,
    resume_from: u64,
    if_range: Option<&str>,
) -> Result<Response, Error> {
    let mut request = client.get(url);
    if resume_from > 0
        && let Some(if_range) = if_range
    {
        request = request
            .header(RANGE, format!("bytes={resume_from}-"))
            .header(IF_RANGE, if_range);
    }
    timeout(RESPONSE_START_TIMEOUT, request.send())
        .await
        .map_err(|_| {
            Error::Network(format!(
                "request did not receive a response within {} seconds",
                RESPONSE_START_TIMEOUT.as_secs()
            ))
        })?
        .map_err(|err| Error::Network(err.to_string()))
}

async fn request_model_range(
    client: &Client,
    url: &str,
    range: RangeDownloadPartMetadata,
    response_metadata: Option<&ResponseMetadata>,
) -> Result<Response, Error> {
    let mut request = client
        .get(url)
        .header(RANGE, format!("bytes={}-{}", range.start, range.end));
    if let Some(if_range) = if_range_header_value(response_metadata) {
        request = request.header(IF_RANGE, if_range);
    }
    timeout(RESPONSE_START_TIMEOUT, request.send())
        .await
        .map_err(|_| {
            Error::Network(format!(
                "request did not receive a response within {} seconds",
                RESPONSE_START_TIMEOUT.as_secs()
            ))
        })?
        .map_err(|err| Error::Network(err.to_string()))
}

async fn fetch_download_probe(client: &Client, url: &str) -> DownloadProbe {
    let response = timeout(RESPONSE_START_TIMEOUT, client.head(url).send())
        .await
        .ok()
        .and_then(Result::ok);
    let Some(response) = response else {
        return DownloadProbe::default();
    };
    if !response.status().is_success() {
        return DownloadProbe::default();
    }
    let content_length = response
        .content_length()
        .filter(|value| *value > 0)
        .or_else(|| {
            // HEAD responses have no body, so reqwest can report a semantic length of 0.
            response
                .headers()
                .get("Content-Length")
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.parse().ok())
                .filter(|value| *value > 0)
        });
    let supports_ranges = response
        .headers()
        .get(ACCEPT_RANGES)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.eq_ignore_ascii_case("bytes"));

    DownloadProbe {
        content_length,
        supports_ranges,
        response_metadata: Some(response_metadata(&response)),
    }
}

pub(crate) async fn probe_content_length(client: &Client, url: &str) -> Option<u64> {
    fetch_download_probe(client, url).await.content_length
}

fn should_use_range_download(total: u64, probe: &DownloadProbe) -> bool {
    total >= MIN_RANGE_DOWNLOAD_BYTES && probe.supports_ranges
}

fn prepare_range_download_metadata(
    target: &Target,
    destination: &Path,
    total: u64,
    response_metadata: Option<ResponseMetadata>,
) -> Result<RangeDownloadMetadata, Error> {
    let tmp_path = tmp_path_for(destination);
    let ranges = range_download_parts(total, RANGE_DOWNLOAD_CONCURRENCY);

    if tmp_path.exists()
        && let Some(metadata) = read_range_download_metadata(destination)
        && file_size(&tmp_path) == Some(total)
        && range_download_metadata_matches(
            &metadata,
            target,
            total,
            response_metadata.as_ref(),
            &ranges,
        )
    {
        return Ok(metadata);
    }

    cleanup_range_download(destination);
    let metadata = RangeDownloadMetadata {
        url: target.url.clone(),
        size_bytes: total,
        etag: response_metadata
            .as_ref()
            .and_then(|metadata| metadata.etag.clone()),
        last_modified: response_metadata
            .as_ref()
            .and_then(|metadata| metadata.last_modified.clone()),
        ranges,
    };
    write_range_download_metadata(&range_metadata_path_for(destination), &metadata)?;
    Ok(metadata)
}

fn range_download_parts(total: u64, concurrency: usize) -> Vec<RangeDownloadPartMetadata> {
    if total == 0 || concurrency == 0 {
        return Vec::new();
    }

    let max_parts = usize::try_from(total).unwrap_or(concurrency);
    let part_count = concurrency.min(max_parts).max(1);
    let part_count_u64 = part_count as u64;
    let base_len = total / part_count_u64;
    let remainder = total % part_count_u64;
    let mut start = 0u64;
    let mut ranges = Vec::with_capacity(part_count);

    for index in 0..part_count {
        let len = base_len + if (index as u64) < remainder { 1 } else { 0 };
        let end = start + len - 1;
        ranges.push(RangeDownloadPartMetadata {
            start,
            end,
            complete: false,
        });
        start = end + 1;
    }

    ranges
}

fn range_download_metadata_matches(
    metadata: &RangeDownloadMetadata,
    target: &Target,
    total: u64,
    response_metadata: Option<&ResponseMetadata>,
    ranges: &[RangeDownloadPartMetadata],
) -> bool {
    metadata.url == target.url
        && metadata.size_bytes == total
        && range_download_validators_match(metadata, response_metadata)
        && metadata.ranges.len() == ranges.len()
        && metadata
            .ranges
            .iter()
            .zip(ranges)
            .all(|(left, right)| left.start == right.start && left.end == right.end)
}

fn range_download_validators_match(
    metadata: &RangeDownloadMetadata,
    response_metadata: Option<&ResponseMetadata>,
) -> bool {
    let Some(response_metadata) = response_metadata else {
        return metadata.etag.is_none() && metadata.last_modified.is_none();
    };

    if let Some(expected_etag) = response_metadata.etag.as_deref() {
        return metadata.etag.as_deref() == Some(expected_etag);
    }
    if let Some(expected_last_modified) = response_metadata.last_modified.as_deref() {
        return metadata.last_modified.as_deref() == Some(expected_last_modified);
    }

    metadata.etag.is_none() && metadata.last_modified.is_none()
}

fn range_download_len(range: RangeDownloadPartMetadata) -> u64 {
    range.end.saturating_sub(range.start).saturating_add(1)
}

fn emit_range_file_progress(
    total_bytes: u64,
    file_started_at: Instant,
    range_states: &Rc<RefCell<Vec<RangePartState>>>,
    on_progress: &Rc<RefCell<&mut dyn FnMut(FileProgress)>>,
) {
    let states = range_states.borrow();
    let downloaded_bytes = states
        .iter()
        .map(|state| state.downloaded_bytes)
        .sum::<u64>()
        .min(total_bytes);
    let network_downloaded_bytes = states
        .iter()
        .map(|state| state.network_downloaded_bytes)
        .sum::<u64>();
    let retry_count = states
        .iter()
        .map(|state| state.retry_count)
        .fold(0u32, u32::saturating_add);
    drop(states);

    let mut callback = on_progress.borrow_mut();
    (**callback)(FileProgress {
        downloaded_bytes,
        total_bytes: Some(total_bytes),
        network_downloaded_bytes,
        elapsed: file_started_at.elapsed(),
        retry_count,
    });
}

fn increment_range_retry(range_states: &Rc<RefCell<Vec<RangePartState>>>, part_index: usize) {
    let mut states = range_states.borrow_mut();
    if let Some(state) = states.get_mut(part_index) {
        state.retry_count = state.retry_count.saturating_add(1);
    }
}

fn mark_range_complete(
    range_metadata: &Rc<RefCell<RangeDownloadMetadata>>,
    range_metadata_path: &Path,
    part_index: usize,
) -> Result<(), Error> {
    let mut metadata = range_metadata.borrow_mut();
    if let Some(range) = metadata.ranges.get_mut(part_index) {
        range.complete = true;
    }
    write_range_download_metadata(range_metadata_path, &metadata)
}

fn validate_range_response(
    response: &Response,
    range: RangeDownloadPartMetadata,
    total: u64,
) -> Result<(), Error> {
    let content_range = response
        .headers()
        .get(CONTENT_RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(parse_content_range)
        .ok_or_else(|| Error::Protocol("range response had no valid Content-Range".to_string()))?;

    if content_range.start != range.start || content_range.end != range.end {
        return Err(Error::Protocol(format!(
            "range mismatch: expected {}-{}, got {}-{}",
            range.start, range.end, content_range.start, content_range.end
        )));
    }

    if let Some(content_total) = content_range.total
        && content_total != total
    {
        return Err(Error::Protocol(format!(
            "range total mismatch: expected {total}, got {content_total}"
        )));
    }

    if let Some(content_length) = response.content_length() {
        let expected_length = range_download_len(range);
        if content_length != expected_length {
            return Err(Error::Protocol(format!(
                "range length mismatch: expected {expected_length}, got {content_length}"
            )));
        }
    }

    Ok(())
}

fn resumed_content_range_start(response: &Response) -> Option<u64> {
    response
        .headers()
        .get(CONTENT_RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(parse_content_range)
        .map(|range| range.start)
}

fn if_range_header_value(response_metadata: Option<&ResponseMetadata>) -> Option<String> {
    response_metadata.and_then(|metadata| {
        metadata
            .etag
            .clone()
            .or_else(|| metadata.last_modified.clone())
    })
}

fn content_total(response: &Response, resume_from: u64) -> Option<u64> {
    let content_range_total = response
        .headers()
        .get(CONTENT_RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(parse_content_range_total);
    let content_length = response.content_length().filter(|value| *value > 0);

    content_range_total.or_else(|| {
        if resume_from > 0 && response.status() == StatusCode::PARTIAL_CONTENT {
            content_length.map(|value| value.saturating_add(resume_from))
        } else {
            content_length
        }
    })
}

fn parse_content_range_total(value: &str) -> Option<u64> {
    parse_content_range(value)?.total
}

fn parse_content_range(value: &str) -> Option<ContentRange> {
    let value = value.trim();
    let value = value.strip_prefix("bytes ")?;
    let (range, total) = value.split_once('/')?;
    let (start, end) = range.split_once('-')?;
    let start = start.parse().ok()?;
    let end = end.parse().ok()?;
    if end < start {
        return None;
    }
    let total = if total == "*" {
        None
    } else {
        Some(total.parse().ok()?)
    };

    Some(ContentRange { start, end, total })
}

enum ProgressPhase<'a> {
    Preparing,
    File {
        label: &'a str,
        index: usize,
        complete: bool,
    },
    Complete,
}

fn emit_progress<F: FnMut(Progress)>(
    phase: ProgressPhase,
    elapsed: Duration,
    total_bytes: Option<u64>,
    file_states: &Rc<RefCell<Vec<FileProgress>>>,
    on_progress: &Rc<RefCell<F>>,
) {
    let states = file_states.borrow();
    let downloaded_bytes = states
        .iter()
        .map(|state| state.downloaded_bytes)
        .sum::<u64>();
    let network_downloaded_bytes = states
        .iter()
        .map(|state| state.network_downloaded_bytes)
        .sum::<u64>();
    let retry_count = states
        .iter()
        .map(|state| state.retry_count)
        .fold(0u32, u32::saturating_add);
    let file_state = match &phase {
        ProgressPhase::File { index, .. } => states.get(*index).copied(),
        _ => None,
    };
    let total_bytes = match phase {
        ProgressPhase::Complete => total_bytes.or(Some(downloaded_bytes)),
        _ => total_bytes.or_else(|| {
            let total = states
                .iter()
                .filter_map(|state| state.total_bytes)
                .sum::<u64>();
            (total > 0).then_some(total)
        }),
    };
    drop(states);

    let (label, file_complete, complete) = match phase {
        ProgressPhase::Preparing => ("Preparing downloads", false, false),
        ProgressPhase::File {
            label, complete, ..
        } => (label, complete, false),
        ProgressPhase::Complete => ("Complete", false, true),
    };
    let percentage = total_bytes
        .filter(|value| *value > 0)
        .map(|total| ((downloaded_bytes as f64 / total as f64) * 100.0).clamp(0.0, 100.0))
        .unwrap_or(0.0);
    let (file_downloaded_bytes, file_total_bytes) = file_state
        .map(|state| (state.downloaded_bytes, state.total_bytes))
        .unwrap_or((0, None));

    on_progress.borrow_mut()(Progress {
        label: label.to_string(),
        downloaded_bytes,
        total_bytes,
        file_downloaded_bytes,
        file_total_bytes,
        percentage,
        elapsed_ms: duration_ms(elapsed),
        bytes_per_second: bytes_per_second(network_downloaded_bytes, elapsed),
        file_elapsed_ms: file_state
            .map(|state| duration_ms(state.elapsed))
            .unwrap_or(0),
        file_bytes_per_second: file_state
            .map(|state| bytes_per_second(state.network_downloaded_bytes, state.elapsed))
            .unwrap_or(0.0),
        retry_count,
        file_retry_count: file_state.map(|state| state.retry_count).unwrap_or(0),
        file_complete,
        complete,
    });
}

fn duration_ms(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

fn bytes_per_second(bytes: u64, elapsed: Duration) -> f64 {
    let seconds = elapsed.as_secs_f64();
    if seconds > 0.0 {
        bytes as f64 / seconds
    } else {
        0.0
    }
}

fn prepare_cached_download(target: &Target, destination: &Path) -> bool {
    if !destination.exists() || check_sha256(destination, &target.sha256, &target.label).is_err() {
        return false;
    }
    cleanup_range_download(destination);
    true
}

fn response_metadata(response: &Response) -> ResponseMetadata {
    ResponseMetadata {
        etag: response
            .headers()
            .get(ETAG)
            .and_then(|value| value.to_str().ok())
            .map(ToString::to_string),
        last_modified: response
            .headers()
            .get(LAST_MODIFIED)
            .and_then(|value| value.to_str().ok())
            .map(ToString::to_string),
    }
}

fn read_range_download_metadata(path: &Path) -> Option<RangeDownloadMetadata> {
    let text = fs::read_to_string(range_metadata_path_for(path)).ok()?;
    serde_json::from_str(&text).ok()
}

fn write_range_download_metadata(
    path: &Path,
    metadata: &RangeDownloadMetadata,
) -> Result<(), Error> {
    let text = serde_json::to_string_pretty(metadata)?;
    fs::write(path, text)?;
    Ok(())
}

pub fn sha256_file(path: &Path) -> Result<String, Error> {
    use std::io::Read;
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1024 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    let mut hex = String::with_capacity(64);
    for byte in hasher.finalize() {
        hex.push_str(&format!("{byte:02x}"));
    }
    Ok(hex)
}

fn check_sha256(path: &Path, expected: &str, label: &str) -> Result<(), Error> {
    let actual = sha256_file(path)?;
    if actual != expected.trim().to_ascii_lowercase() {
        return Err(Error::Validation(format!(
            "{label} checksum mismatch: expected {expected}, got {actual}"
        )));
    }
    Ok(())
}

fn range_metadata_path_for(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.tmp.ranges.json", path.display()))
}

fn partial_metadata_path_for(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.tmp.partial.json", path.display()))
}

fn partial_download_validator(destination: &Path, url: &str) -> Option<String> {
    let text = fs::read_to_string(partial_metadata_path_for(destination)).ok()?;
    let metadata: PartialDownloadMetadata = serde_json::from_str(&text).ok()?;
    if metadata.url != url {
        return None;
    }
    metadata.etag.or(metadata.last_modified)
}

fn write_partial_download_metadata(
    destination: &Path,
    target: &Target,
    response_metadata: &ResponseMetadata,
) -> Result<(), Error> {
    let metadata = PartialDownloadMetadata {
        url: target.url.clone(),
        etag: response_metadata.etag.clone(),
        last_modified: response_metadata.last_modified.clone(),
    };
    let text = serde_json::to_string_pretty(&metadata)?;
    fs::write(partial_metadata_path_for(destination), text)?;
    Ok(())
}

fn cleanup_range_download(destination: &Path) {
    let _ = fs::remove_file(tmp_path_for(destination));
    let _ = fs::remove_file(range_metadata_path_for(destination));
    let _ = fs::remove_file(partial_metadata_path_for(destination));
}

#[cfg(test)]
fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| u64::try_from(duration.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

fn existing_download_bytes(
    target: &Target,
    destination: &Path,
    probe: &DownloadProbe,
    cached: bool,
) -> u64 {
    if cached {
        return file_size(destination).unwrap_or(0);
    }
    if destination.exists() {
        return 0;
    }

    if range_metadata_path_for(destination).exists() {
        if let Some(total) = probe.content_length {
            let ranges = range_download_parts(total, RANGE_DOWNLOAD_CONCURRENCY);
            if let Some(metadata) = read_range_download_metadata(destination)
                && file_size(&tmp_path_for(destination)) == Some(total)
                && range_download_metadata_matches(
                    &metadata,
                    target,
                    total,
                    probe.response_metadata.as_ref(),
                    &ranges,
                )
            {
                return metadata
                    .ranges
                    .iter()
                    .filter(|range| range.complete)
                    .map(|range| range_download_len(*range))
                    .sum();
            }
        }
        return 0;
    }

    0
}

fn file_size(path: &Path) -> Option<u64> {
    fs::metadata(path).ok().map(|metadata| metadata.len())
}

fn tmp_path_for(destination: &Path) -> PathBuf {
    PathBuf::from(format!("{}.tmp", destination.display()))
}

#[cfg(unix)]
fn write_all_at(file: &File, mut bytes: &[u8], mut offset: u64) -> std::io::Result<()> {
    use std::os::unix::fs::FileExt;

    while !bytes.is_empty() {
        let written = file.write_at(bytes, offset)?;
        if written == 0 {
            return Err(std::io::Error::new(
                ErrorKind::WriteZero,
                "failed to write range bytes",
            ));
        }
        offset = offset.saturating_add(written as u64);
        bytes = &bytes[written..];
    }

    Ok(())
}

#[cfg(windows)]
fn write_all_at(file: &File, mut bytes: &[u8], mut offset: u64) -> std::io::Result<()> {
    use std::os::windows::fs::FileExt;

    while !bytes.is_empty() {
        let written = file.seek_write(bytes, offset)?;
        if written == 0 {
            return Err(std::io::Error::new(
                ErrorKind::WriteZero,
                "failed to write range bytes",
            ));
        }
        offset = offset.saturating_add(written as u64);
        bytes = &bytes[written..];
    }

    Ok(())
}

#[cfg(not(any(unix, windows)))]
fn write_all_at(file: &File, bytes: &[u8], offset: u64) -> std::io::Result<()> {
    use std::io::{Seek, SeekFrom};

    let mut file = file.try_clone()?;
    file.seek(SeekFrom::Start(offset))?;
    file.write_all(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::net::{TcpListener, TcpStream};
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::thread;

    #[test]
    fn range_download_parts_split_file_into_four_ranges() {
        let ranges = range_download_parts(10, 4);

        assert_eq!(
            ranges,
            vec![
                RangeDownloadPartMetadata {
                    start: 0,
                    end: 2,
                    complete: false,
                },
                RangeDownloadPartMetadata {
                    start: 3,
                    end: 5,
                    complete: false,
                },
                RangeDownloadPartMetadata {
                    start: 6,
                    end: 7,
                    complete: false,
                },
                RangeDownloadPartMetadata {
                    start: 8,
                    end: 9,
                    complete: false,
                },
            ]
        );
        assert_eq!(
            ranges
                .iter()
                .map(|range| range_download_len(*range))
                .sum::<u64>(),
            10
        );
    }

    #[test]
    fn range_download_parts_do_not_create_empty_ranges() {
        let ranges = range_download_parts(3, 4);

        assert_eq!(ranges.len(), 3);
        assert!(ranges.iter().all(|range| range_download_len(*range) == 1));
    }

    #[test]
    fn parse_content_range_accepts_known_and_unknown_totals() {
        assert_eq!(
            parse_content_range("bytes 10-19/100"),
            Some(ContentRange {
                start: 10,
                end: 19,
                total: Some(100),
            })
        );
        assert_eq!(
            parse_content_range("bytes 10-19/*"),
            Some(ContentRange {
                start: 10,
                end: 19,
                total: None,
            })
        );
    }

    #[test]
    fn parse_content_range_rejects_invalid_ranges() {
        assert_eq!(parse_content_range("bytes 20-10/100"), None);
        assert_eq!(parse_content_range("items 10-19/100"), None);
        assert_eq!(parse_content_range("bytes 10-19/not-a-number"), None);
    }

    #[test]
    fn download_uses_four_ranges_when_server_supports_ranges() {
        let bytes = Arc::new(sample_bytes(MIN_RANGE_DOWNLOAD_BYTES as usize + 123));
        let head_count = Arc::new(AtomicUsize::new(0));
        let range_get_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));
        let running = Arc::new(AtomicBool::new(true));

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind test server");
        listener
            .set_nonblocking(true)
            .expect("configure test server");
        let address = listener.local_addr().expect("test server address");
        let server = {
            let bytes = Arc::clone(&bytes);
            let head_count = Arc::clone(&head_count);
            let range_get_count = Arc::clone(&range_get_count);
            let full_get_count = Arc::clone(&full_get_count);
            let running = Arc::clone(&running);
            thread::spawn(move || {
                while running.load(Ordering::SeqCst) {
                    match listener.accept() {
                        Ok((stream, _)) => {
                            stream.set_nonblocking(false).ok();
                            let bytes = Arc::clone(&bytes);
                            let head_count = Arc::clone(&head_count);
                            let range_get_count = Arc::clone(&range_get_count);
                            let full_get_count = Arc::clone(&full_get_count);
                            thread::spawn(move || {
                                handle_range_test_request(
                                    stream,
                                    bytes,
                                    head_count,
                                    range_get_count,
                                    full_get_count,
                                );
                            });
                        }
                        Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                            thread::sleep(Duration::from_millis(5));
                        }
                        Err(_) => break,
                    }
                }
            })
        };

        let test_dir = scratch_dir("range-download");
        let destination = test_dir.join("model.bin");
        let url = format!("http://{address}/model.bin");

        let probe_client = Client::builder().build().expect("build probe client");
        let probe_runtime = Builder::new_current_thread()
            .enable_io()
            .enable_time()
            .build()
            .expect("build probe runtime");
        let probe = probe_runtime.block_on(fetch_download_probe(&probe_client, &url));
        assert_eq!(probe.content_length, Some(bytes.len() as u64));
        assert!(probe.supports_ranges);

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url,
                destination: destination.clone(),
                sha256: sha_hex(&bytes),
            }],
            |_| {},
            || false,
        );

        running.store(false, Ordering::SeqCst);
        let _ = TcpStream::connect(address);
        server.join().expect("join test server");

        result.expect("range download succeeds");
        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );
        assert_eq!(head_count.load(Ordering::SeqCst), 2);
        assert_eq!(
            range_get_count.load(Ordering::SeqCst),
            RANGE_DOWNLOAD_CONCURRENCY,
            "full GET count: {}",
            full_get_count.load(Ordering::SeqCst)
        );
        assert_eq!(full_get_count.load(Ordering::SeqCst), 0);
        assert!(!range_metadata_path_for(&destination).exists());

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn download_uses_single_stream_when_server_lacks_range_support() {
        let bytes = Arc::new(sample_bytes(MIN_RANGE_DOWNLOAD_BYTES as usize + 123));
        let get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("single-download");
        let destination = test_dir.join("model.bin");

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: server.url("/model.bin"),
                destination: destination.clone(),
                sha256: sha_hex(&bytes),
            }],
            |_| {},
            || false,
        );

        result.expect("single-stream download succeeds");
        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );
        assert_eq!(get_count.load(Ordering::SeqCst), 1);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn downloads_files_sequentially() {
        let bytes = Arc::new(sample_bytes(512));
        let active = Arc::new(AtomicUsize::new(0));
        let max_active = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let active = Arc::clone(&active);
            let max_active = Arc::clone(&max_active);
            TestServer::spawn(move |stream| {
                let current = active.fetch_add(1, Ordering::SeqCst) + 1;
                max_active.fetch_max(current, Ordering::SeqCst);
                thread::sleep(Duration::from_millis(50));
                handle_no_range_test_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::new(AtomicUsize::new(0)),
                );
                active.fetch_sub(1, Ordering::SeqCst);
            })
        };

        let test_dir = scratch_dir("sequential-downloads");
        let targets = ["model", "projector"].map(|label| Target {
            label: label.to_string(),
            url: server.url(&format!("/{label}.bin")),
            destination: test_dir.join(format!("{label}.bin")),
            sha256: sha_hex(&bytes),
        });

        fetch(
            &Downloader::new().unwrap(),
            targets.into(),
            |_| {},
            || false,
        )
        .expect("downloads succeed");
        assert_eq!(max_active.load(Ordering::SeqCst), 1);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn completed_download_is_served_from_cache() {
        let bytes = Arc::new(sample_bytes(MIN_RANGE_DOWNLOAD_BYTES as usize + 123));
        let head_count = Arc::new(AtomicUsize::new(0));
        let range_get_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let head_count = Arc::clone(&head_count);
            let range_get_count = Arc::clone(&range_get_count);
            let full_get_count = Arc::clone(&full_get_count);
            TestServer::spawn(move |stream| {
                handle_range_test_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::clone(&head_count),
                    Arc::clone(&range_get_count),
                    Arc::clone(&full_get_count),
                );
            })
        };

        let test_dir = scratch_dir("cache-skip-download");
        let destination = test_dir.join("model.bin");
        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };

        fetch(
            &Downloader::new().unwrap(),
            vec![target.clone()],
            |_| {},
            || false,
        )
        .expect("first download succeeds");
        let requests_after_first =
            head_count.load(Ordering::SeqCst) + range_get_count.load(Ordering::SeqCst);
        assert!(requests_after_first > 0);

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("second download succeeds");
        assert_eq!(
            head_count.load(Ordering::SeqCst) + range_get_count.load(Ordering::SeqCst),
            requests_after_first,
            "cached download must not hit the network again"
        );
        assert_eq!(fs::read(&destination).expect("read cached file"), *bytes);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn cache_hit_is_revalidated_and_reheals_on_corruption() {
        let bytes = Arc::new(sample_bytes(512));
        let get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("revalidate-download");
        let destination = test_dir.join("model.bin");
        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };

        fetch(
            &Downloader::new().unwrap(),
            vec![target.clone()],
            |_| {},
            || false,
        )
        .expect("first download succeeds");
        assert_eq!(get_count.load(Ordering::SeqCst), 1);

        let mut data = fs::read(&destination).expect("read cached file");
        data[0] = data[0].wrapping_add(1);
        fs::write(&destination, &data).expect("corrupt cached file");

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("second download re-heals the corrupt cache");
        assert_eq!(
            get_count.load(Ordering::SeqCst),
            2,
            "corrupt cache must be re-downloaded, not served"
        );
        assert_eq!(fs::read(&destination).expect("read healed file"), *bytes);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn existing_valid_file_without_sidecar_is_adopted() {
        let bytes = Arc::new(sample_bytes(512));
        let get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("adopt-download");
        let destination = test_dir.join("model.bin");
        fs::write(&destination, bytes.as_slice()).expect("place existing file");

        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("fetch adopts existing file");

        assert_eq!(
            get_count.load(Ordering::SeqCst),
            0,
            "an existing valid file must not be re-downloaded"
        );
        assert_eq!(fs::read(&destination).expect("read adopted file"), *bytes);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn single_stream_download_resumes_from_partial_tmp() {
        let bytes = Arc::new(sample_bytes(512));
        let head_count = Arc::new(AtomicUsize::new(0));
        let range_get_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let head_count = Arc::clone(&head_count);
            let range_get_count = Arc::clone(&range_get_count);
            let full_get_count = Arc::clone(&full_get_count);
            TestServer::spawn(move |stream| {
                handle_range_test_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::clone(&head_count),
                    Arc::clone(&range_get_count),
                    Arc::clone(&full_get_count),
                );
            })
        };

        let test_dir = scratch_dir("resume-download");
        let destination = test_dir.join("model.bin");
        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };
        fs::write(tmp_path_for(&destination), &bytes[..256]).expect("place partial tmp");
        write_partial_download_metadata(
            &destination,
            &target,
            &ResponseMetadata {
                etag: Some("\"test-etag\"".to_string()),
                last_modified: None,
            },
        )
        .expect("write partial sidecar");

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("resume succeeds");

        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );
        assert_eq!(
            range_get_count.load(Ordering::SeqCst),
            1,
            "resume must continue with a single ranged GET"
        );
        assert_eq!(full_get_count.load(Ordering::SeqCst), 0);
        assert!(!tmp_path_for(&destination).exists());
        assert!(!partial_metadata_path_for(&destination).exists());

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn single_stream_download_restarts_when_resume_validator_is_stale() {
        let bytes = Arc::new(sample_bytes(512));
        let head_count = Arc::new(AtomicUsize::new(0));
        let range_get_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let head_count = Arc::clone(&head_count);
            let range_get_count = Arc::clone(&range_get_count);
            let full_get_count = Arc::clone(&full_get_count);
            TestServer::spawn(move |stream| {
                handle_range_test_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::clone(&head_count),
                    Arc::clone(&range_get_count),
                    Arc::clone(&full_get_count),
                );
            })
        };

        let test_dir = scratch_dir("stale-resume-download");
        let destination = test_dir.join("model.bin");
        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };
        fs::write(tmp_path_for(&destination), vec![0xAAu8; 256]).expect("place stale tmp");
        write_partial_download_metadata(
            &destination,
            &target,
            &ResponseMetadata {
                etag: Some("\"other-etag\"".to_string()),
                last_modified: None,
            },
        )
        .expect("write stale partial sidecar");

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("restart succeeds");

        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );
        assert_eq!(
            full_get_count.load(Ordering::SeqCst),
            1,
            "a stale validator must trigger a full restart, not an append"
        );
        assert_eq!(range_get_count.load(Ordering::SeqCst), 0);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn single_stream_download_ignores_partial_without_sidecar() {
        let bytes = Arc::new(sample_bytes(512));
        let get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("no-sidecar-resume-download");
        let destination = test_dir.join("model.bin");
        fs::write(tmp_path_for(&destination), &bytes[..256]).expect("place orphan tmp");

        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("fresh download succeeds");

        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );
        assert_eq!(
            get_count.load(Ordering::SeqCst),
            1,
            "a partial without a sidecar must restart from scratch"
        );

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn single_stream_resume_restarts_when_server_resumes_from_wrong_offset() {
        let bytes = Arc::new(sample_bytes(512));
        let bad_resume_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));

        let server = {
            let bytes = Arc::clone(&bytes);
            let bad_resume_count = Arc::clone(&bad_resume_count);
            let full_get_count = Arc::clone(&full_get_count);
            TestServer::spawn(move |stream| {
                handle_wrong_offset_resume_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::clone(&bad_resume_count),
                    Arc::clone(&full_get_count),
                );
            })
        };

        let test_dir = scratch_dir("wrong-offset-resume");
        let destination = test_dir.join("model.bin");
        let target = Target {
            label: "Model".to_string(),
            url: server.url("/model.bin"),
            destination: destination.clone(),
            sha256: sha_hex(&bytes),
        };
        fs::write(tmp_path_for(&destination), &bytes[..256]).expect("place partial tmp");
        write_partial_download_metadata(
            &destination,
            &target,
            &ResponseMetadata {
                etag: Some("\"test-etag\"".to_string()),
                last_modified: None,
            },
        )
        .expect("write partial sidecar");

        fetch(&Downloader::new().unwrap(), vec![target], |_| {}, || false)
            .expect("restart after bad 206 succeeds");

        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes,
            "a wrong-offset 206 must never append duplicate bytes"
        );
        assert_eq!(bad_resume_count.load(Ordering::SeqCst), 1);
        assert_eq!(
            full_get_count.load(Ordering::SeqCst),
            1,
            "the retry must restart from scratch"
        );

        let _ = fs::remove_dir_all(test_dir);
    }

    fn handle_wrong_offset_resume_request(
        mut stream: TcpStream,
        bytes: Arc<Vec<u8>>,
        bad_resume_count: Arc<AtomicUsize>,
        full_get_count: Arc<AtomicUsize>,
    ) {
        let mut reader = BufReader::new(stream.try_clone().expect("clone test stream"));
        let mut request_line = String::new();
        if reader.read_line(&mut request_line).is_err() {
            return;
        }
        let mut has_range = false;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).is_err() || line == "\r\n" || line.is_empty() {
                break;
            }
            if let Some((name, _)) = line.split_once(':')
                && name.eq_ignore_ascii_case("range")
            {
                has_range = true;
            }
        }

        if request_line.starts_with("HEAD ") {
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nETag: \"test-etag\"\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            let _ = stream.write_all(response.as_bytes());
            return;
        }

        if has_range {
            bad_resume_count.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                "HTTP/1.1 206 Partial Content\r\nContent-Length: {len}\r\nContent-Range: bytes 0-{end}/{len}\r\nETag: \"test-etag\"\r\nConnection: close\r\n\r\n",
                len = bytes.len(),
                end = bytes.len() - 1
            );
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.write_all(bytes.as_slice());
        } else {
            full_get_count.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.write_all(bytes.as_slice());
        }
    }

    #[test]
    fn cancelled_fetch_returns_the_cancelled_variant() {
        let test_dir = scratch_dir("cancel-download");
        let destination = test_dir.join("model.bin");

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: "http://127.0.0.1:1/model.bin".to_string(),
                destination: destination.clone(),
                sha256: "0".repeat(64),
            }],
            |_| {},
            || true,
        );

        assert!(matches!(result, Err(Error::Cancelled)));

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn cached_download_adoption_removes_stale_partials() {
        let test_dir = scratch_dir("cached-adoption");
        let destination = test_dir.join("model.bin");
        fs::write(&destination, b"complete-model").expect("write model");
        fs::write(tmp_path_for(&destination), b"stale").expect("write tmp");
        fs::write(range_metadata_path_for(&destination), "{}").expect("write ranges sidecar");
        fs::write(partial_metadata_path_for(&destination), "{}").expect("write partial sidecar");

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: "http://127.0.0.1:1/model.bin".to_string(),
                destination: destination.clone(),
                sha256: sha_hex(b"complete-model"),
            }],
            |_| {},
            || false,
        );

        assert!(result.is_ok());
        assert!(destination.exists());
        assert!(!tmp_path_for(&destination).exists());
        assert!(!range_metadata_path_for(&destination).exists());
        assert!(!partial_metadata_path_for(&destination).exists());

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn sha_pinned_download_verifies_content() {
        let bytes = Arc::new(sample_bytes(2048));
        let get_count = Arc::new(AtomicUsize::new(0));
        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("sha-download");
        let destination = test_dir.join("model.bin");
        let mut expected = String::new();
        for byte in Sha256::digest(bytes.as_slice()) {
            expected.push_str(&format!("{byte:02x}"));
        }

        fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: server.url("/model.bin"),
                destination: destination.clone(),
                sha256: expected,
            }],
            |_| {},
            || false,
        )
        .expect("sha-pinned download succeeds");
        assert_eq!(
            fs::read(&destination).expect("read downloaded file"),
            *bytes
        );

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn sha_mismatch_fails_immediately_without_installing() {
        let bytes = Arc::new(sample_bytes(2048));
        let get_count = Arc::new(AtomicUsize::new(0));
        let server = {
            let bytes = Arc::clone(&bytes);
            let get_count = Arc::clone(&get_count);
            TestServer::spawn(move |stream| {
                handle_no_range_test_request(stream, Arc::clone(&bytes), Arc::clone(&get_count));
            })
        };

        let test_dir = scratch_dir("sha-mismatch");
        let destination = test_dir.join("model.bin");

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: server.url("/model.bin"),
                destination: destination.clone(),
                sha256: "0".repeat(64),
            }],
            |_| {},
            || false,
        );

        assert!(result.is_err());
        assert!(!destination.exists());
        assert_eq!(get_count.load(Ordering::SeqCst), 1);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn ranged_sha_mismatch_fails_without_single_stream_fallback() {
        let bytes = Arc::new(sample_bytes(MIN_RANGE_DOWNLOAD_BYTES as usize + 123));
        let head_count = Arc::new(AtomicUsize::new(0));
        let range_get_count = Arc::new(AtomicUsize::new(0));
        let full_get_count = Arc::new(AtomicUsize::new(0));
        let server = {
            let bytes = Arc::clone(&bytes);
            let head_count = Arc::clone(&head_count);
            let range_get_count = Arc::clone(&range_get_count);
            let full_get_count = Arc::clone(&full_get_count);
            TestServer::spawn(move |stream| {
                handle_range_test_request(
                    stream,
                    Arc::clone(&bytes),
                    Arc::clone(&head_count),
                    Arc::clone(&range_get_count),
                    Arc::clone(&full_get_count),
                );
            })
        };

        let test_dir = scratch_dir("ranged-sha-mismatch");
        let destination = test_dir.join("model.bin");

        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                label: "Model".to_string(),
                url: server.url("/model.bin"),
                destination: destination.clone(),
                sha256: "0".repeat(64),
            }],
            |_| {},
            || false,
        );

        assert!(result.is_err());
        assert!(!destination.exists());
        assert!(!tmp_path_for(&destination).exists());
        assert_eq!(
            range_get_count.load(Ordering::SeqCst),
            RANGE_DOWNLOAD_CONCURRENCY
        );
        assert_eq!(full_get_count.load(Ordering::SeqCst), 0);

        let _ = fs::remove_dir_all(test_dir);
    }

    #[test]
    fn sha_pinned_target_adopts_cached_file_regardless_of_url() {
        let test_dir = scratch_dir("sha-cached");
        let destination = test_dir.join("model.bin");
        fs::write(&destination, b"model-bytes").expect("write cached file");
        let sha = sha256_file(&destination).expect("hash cached file");
        let old_target = Target {
            label: "Model".to_string(),
            url: "http://cache.example.org/old-location".to_string(),
            destination: destination.clone(),
            sha256: sha.clone(),
        };

        fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                url: "http://127.0.0.1:9/new-location".to_string(),
                ..old_target.clone()
            }],
            |_| {},
            || false,
        )
        .expect("cached file adopted by checksum despite changed URL");

        fs::write(&destination, b"corrupted").expect("corrupt cached file");
        let result = fetch(
            &Downloader::new().unwrap(),
            vec![Target {
                url: "http://127.0.0.1:9/new-location".to_string(),
                ..old_target
            }],
            |_| {},
            || false,
        );
        assert!(result.is_err());

        let _ = fs::remove_dir_all(test_dir);
    }

    fn sample_bytes(len: usize) -> Vec<u8> {
        (0..len).map(|index| (index % 251) as u8).collect()
    }

    fn sha_hex(bytes: &[u8]) -> String {
        let mut hex = String::with_capacity(64);
        for byte in Sha256::digest(bytes) {
            hex.push_str(&format!("{byte:02x}"));
        }
        hex
    }

    fn scratch_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ensu-{name}-test-{}", now_ms()));
        fs::create_dir_all(&dir).expect("create test dir");
        dir
    }

    struct TestServer {
        address: std::net::SocketAddr,
        running: Arc<AtomicBool>,
        handle: Option<thread::JoinHandle<()>>,
    }

    impl TestServer {
        fn spawn(handler: impl Fn(TcpStream) + Send + Sync + 'static) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").expect("bind test server");
            listener
                .set_nonblocking(true)
                .expect("configure test server");
            let address = listener.local_addr().expect("test server address");
            let running = Arc::new(AtomicBool::new(true));
            let handler: Arc<dyn Fn(TcpStream) + Send + Sync> = Arc::new(handler);
            let handle = {
                let running = Arc::clone(&running);
                thread::spawn(move || {
                    while running.load(Ordering::SeqCst) {
                        match listener.accept() {
                            Ok((stream, _)) => {
                                stream.set_nonblocking(false).ok();
                                let handler = Arc::clone(&handler);
                                thread::spawn(move || handler(stream));
                            }
                            Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                                thread::sleep(Duration::from_millis(5));
                            }
                            Err(_) => break,
                        }
                    }
                })
            };
            Self {
                address,
                running,
                handle: Some(handle),
            }
        }

        fn url(&self, path: &str) -> String {
            format!("http://{}{}", self.address, path)
        }
    }

    impl Drop for TestServer {
        fn drop(&mut self) {
            self.running.store(false, Ordering::SeqCst);
            let _ = TcpStream::connect(self.address);
            if let Some(handle) = self.handle.take() {
                let _ = handle.join();
            }
        }
    }

    fn handle_no_range_test_request(
        mut stream: TcpStream,
        bytes: Arc<Vec<u8>>,
        get_count: Arc<AtomicUsize>,
    ) {
        let mut reader = BufReader::new(stream.try_clone().expect("clone test stream"));
        let mut request_line = String::new();
        if reader.read_line(&mut request_line).is_err() {
            return;
        }
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).is_err() || line == "\r\n" || line.is_empty() {
                break;
            }
        }

        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            bytes.len()
        );
        let _ = stream.write_all(response.as_bytes());
        if request_line.starts_with("HEAD ") {
            return;
        }
        get_count.fetch_add(1, Ordering::SeqCst);
        let _ = stream.write_all(bytes.as_slice());
    }

    fn handle_range_test_request(
        mut stream: TcpStream,
        bytes: Arc<Vec<u8>>,
        head_count: Arc<AtomicUsize>,
        range_get_count: Arc<AtomicUsize>,
        full_get_count: Arc<AtomicUsize>,
    ) {
        let mut reader = BufReader::new(stream.try_clone().expect("clone test stream"));
        let mut request_line = String::new();
        if reader.read_line(&mut request_line).is_err() {
            return;
        }

        let mut range_header = None;
        let mut if_range_header = None;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).is_err() || line == "\r\n" || line.is_empty() {
                break;
            }
            if let Some((name, value)) = line.split_once(':') {
                if name.eq_ignore_ascii_case("range") {
                    range_header = Some(value.trim().to_string());
                } else if name.eq_ignore_ascii_case("if-range") {
                    if_range_header = Some(value.trim().to_string());
                }
            }
        }

        if request_line.starts_with("HEAD ") {
            head_count.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nETag: \"test-etag\"\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            let _ = stream.write_all(response.as_bytes());
            return;
        }

        let resume_allowed = if_range_header
            .as_deref()
            .is_none_or(|value| value == "\"test-etag\"");
        if let Some(range_header) = range_header.filter(|_| resume_allowed) {
            let Some((start, end)) = parse_test_range_header(&range_header, bytes.len() as u64)
            else {
                let _ = stream
                    .write_all(b"HTTP/1.1 416 Range Not Satisfiable\r\nConnection: close\r\n\r\n");
                return;
            };
            range_get_count.fetch_add(1, Ordering::SeqCst);
            let body = &bytes[start as usize..=end as usize];
            let response = format!(
                "HTTP/1.1 206 Partial Content\r\nContent-Length: {}\r\nContent-Range: bytes {}-{}/{}\r\nAccept-Ranges: bytes\r\nETag: \"test-etag\"\r\nConnection: close\r\n\r\n",
                body.len(),
                start,
                end,
                bytes.len()
            );
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.write_all(body);
        } else {
            full_get_count.fetch_add(1, Ordering::SeqCst);
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nETag: \"test-etag\"\r\nConnection: close\r\n\r\n",
                bytes.len()
            );
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.write_all(bytes.as_slice());
        }
    }

    fn parse_test_range_header(value: &str, total: u64) -> Option<(u64, u64)> {
        let value = value.strip_prefix("bytes=")?;
        let (start, end) = value.split_once('-')?;
        let start = start.parse().ok()?;
        let end = if end.is_empty() {
            total.checked_sub(1)?
        } else {
            end.parse().ok()?
        };
        if start > end || end >= total {
            return None;
        }
        Some((start, end))
    }
}
